#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# update-keystores.sh - Installs and verifies TLS certificates in our keystores. Encrypts with ansible-vault.
#
# Usage: 
#   update-keystores.sh [-h|--help] [-d|--update-ca-certs] [-e|--environment name] [-s|--source-dir path] <output directory>
#
# ---------------------------------------------------------------------------
PROGNAME=${0##*/}

# Store and key passwords. These default to 'changeit', but you can overide by setting and exporting
# 'STORE_PASS' or 'KEY_PASS' environment variables.
STORE_PASS="${STORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
VAULT_PASS="${VAULT_PASS:-}"

# URL's to the CA certs that was used to sign our certificates
fed_root="https://ocio.nih.gov/Smartcard/Documents/Certificates/Federal_CP_Root_SHA256.cer"
entrust_root="https://ocio.nih.gov/Smartcard/Documents/Entrust%20Managed%20Services%20Root%20CA.cer"
intermediate="https://ocio.nih.gov/Smartcard/Documents/HHS-FPKI-Intermediate.cer"
ca_cert_urls=("$fed_root" "$entrust_root" "$intermediate")

# ca_cert_chain - An array containing the CA root/intermediate certificate chain certificates.
# The --update-ca-certs option downloads the chain using the url's above. We also convert the chain
# to PEM format and do some renaming to make them script friendly.
ca_certs=("federal_cp_root_sha256.pem" "entrust_managed_services_root_ca.pem" "hhs_fpki_intermediate.pem")


# program variables
tmp_dir=$(mktemp -d -t bfd-certs-XXXXXXXXXX)
dst_dir="${dst_dir:-$(pwd)}"
src_dir=
environments=()
default_environments=(prod prod-sbx test)
downloaded_ca_certs=false
force=false


# Perform pre-exit housekeeping
clean_up() {
  rm -rf "$tmp_dir"
}

error_exit() {
  echo
  echo -e "$1" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

# Handle trapped signals
signal_exit() {
  case "$1" in
    INT)
      error_exit "Aborting." ;;
    TERM)
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}


usage() {
  echo -e "Usage: $PROGNAME -s|--source-dir /path/to/certs/dir [-h|--help] [-u|--update-ca-certs] \
[-e|--environment name] [-f|--force] [<destination directory>]"
}

help_message() {
  cat <<- _EOF_
  $PROGNAME - Exports encrypted BFD keystores with our TLS certificates installed
  - Installs BFD's CA root, intermediate, and signed TLS certificates into appropriate keystores
  - Downloads CA root certificate chain if desired
  - Encrypts with ansible-vault
  - Exports encrypted keystore to the <destination directory> - defaults to current working directory (.)

  $(usage)

  Examples:
    # Build all environments keystores (prod, prod-sbx, and test) and export to ~/Desktop.
    ./$PROGNAME --source-dir /path/to/Keybase/dir ~/Desktop

    # Just build nad export the test and prod-sbx keystores and do not prompt to overwrite existing files.
    ./$PROGNAME --source-dir /path/to/Keybase/dir -e test -e prod-sbx --force ../../ansible/playbooks-ccs/files

    # Download the CA root chain from the internet and then build and export all to the current working directory.
    ./$PROGNAME --source-dir /path/to/Keybase/dir --update-ca-certs

  Options:
  -h, --help  Display this help message and exit.
  -s, --source-dir path  [Required] Source directory containing our keystores and signed certs.
    Where 'path' is the Path to source directory. This could be /Volumes/Keybase/....
  [-u, --update-ca-certs]  Download root and intermediate CA certificates.
  [-e, --environment name]  Specify one or more environment(s) to process. I.e. '-e prod -e test'.
    Where 'name' is the Name of the environment. E.g., prod prod-sbx or test. Defaults to all.
  [-f, --force] Do not prompt for user input. Warning! This may overwrite existing files.

_EOF_
  return
}


# ensures we have openssl and keytool installed and makes sure we are not using the default MacOS openssl
check_tools(){
  printf "Checking tools..."
  # keytool
  (command -v keytool >/dev/null 2>&1) || error_exit "Missing 'keytool' command. Please install Java."

  # openssl
  (command -v openssl >/dev/null 2>&1) || error_exit "You need 'openssl' installed to run this script."
  if [[ "$(openssl version)" =~ "LibreSSL" ]]; then
    error_exit "LibreSSL based openssl is incompatible with our keystores. Please 'brew install openssl'\
    follow the directions to add to your \$PATH"
  fi

  # curl
  if [[ "$download_certs" == "true" ]]; then
    (command -v curl >/dev/null 2>&1) || error_exit "You need 'curl' installed if you wish to download certs."
  fi

  # ansible-vault
  (command -v ansible-vault >/dev/null 2>&1) || error_exit "Missing 'ansible-vault' command. Please install ansible."

  
  echo " OK"
}

# ensures we have access to our keystores and certificates
check_files(){
  local missing_files=()

  printf "Checking files... "
  # CA certificates
  if [[ "$downloaded_ca_certs" == "false" ]]; then
    # try to copy the CA certificates from src_dir to tmp_dir
    for ca_cert in "${ca_certs[@]}"; do
      if [[ -f "$src_dir"/"$ca_cert" ]]; then
        cp "$src_dir"/"$ca_cert" "$tmp_dir"
      fi
    done
  fi

  # CA certs should all be in tmp_dir by now.. verify
  for ca_cert in "${ca_certs[@]}"; do
    [ ! -f "$tmp_dir"/"$ca_cert" ] && missing_files+=("$ca_cert")
  done
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing one or more CA certificates in the source directory:"
    for f in "${missing_files[@]}"; do
      echo "  - $f"
    done
    echo "Maybe run with '--update-ca-certs' option to download them."
    error_exit "Exiting."
  fi
  
  # check for keystores and signed certificates
  missing_files=()
  for environment in "${environments[@]}"; do
    [ ! -f "${src_dir}/${environment}_bfd_cms_gov.jks" ] && missing_files+=("${environment}_bfd_cms_gov.jks")
    [ ! -f "${src_dir}/${environment}.bfd.cms.gov.pem" ] && missing_files+=("${environment}.bfd.cms.gov.pem")
  done
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing keystores or certificates in the source directory:"
    for f in "${missing_files[@]}"; do
      echo "  - $f"
    done
    error_exit "Exiting."
  fi
  echo " OK"
}

fetch_certs(){
  local ca_exists=false
  for cer in "${ca_certs[@]}"; do
    [[ -f "$src_dir"/"$cer" ]] && ca_exists=true
    [[ -f "$dst_dir"/"$cer" ]] && ca_exists=true
  done

  if [[ "$force" == "false" ]] && [[ "$ca_exists" == "true" ]]; then
    read -r -p "Overwrite existing CA certs in source directory? [y/n] " response
    if [[ ! "$response" == "y" ]]; then
      error_exit "Aborting."
    fi
  fi

  printf "Downloading CA certificates"
  for ca_url in "${ca_cert_urls[@]}"; do
    (cd "$tmp_dir"; curl -O "$ca_url" >/dev/null 2>&1) || error_exit "Failed to download CA certifcate from $ca_url"
    printf "."
  done
  echo " OK"

  # convert from DER to PEM and cleanup the file names
  printf "Preparing CA certificates"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    for cer in *.cer; do
      openssl x509 -in "$cer" -inform DER > "${cer%%.*}.tmp"
    done
  )

  # export
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    for p in *.tmp; do
      local lower="${p,,}"                      # convert to lower case
      local fix_spaces="${lower//%20/_}"        # replace %20 with _
      local underscores="${fix_spaces// /_}"    # replace spaces with underscores
      local dashes="${underscores//-/_}"        # replace dashes with underscores
      local pem="${dashes%%.*}.pem"             # rename
      cp -f "$p" "$tmp_dir"/"$pem"              # copy to our tmp working directory
      printf "."
    done
  )
  downloaded_ca_certs=true
  echo " OK"
}

# import certs, export, and encrypt
import_root_chain(){
  local keystore="$1"
  printf "Importing root chain"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    
    # import the CA chain in order
    for ca_cert in "${ca_certs[@]}"; do
      keytool -importcert -noprompt -alias "$ca_cert" -trustcacerts -keystore "$keystore" -storepass "$STORE_PASS" -file "$ca_cert" 2>/dev/null
      printf "."
      rm "$ca_cert"
    done
  )
  echo " OK"
}

import_signed_cert(){
  local environment="$1"
  local keystore="$2"
  local signed_cert="$3"
  printf "Importing %s's signed cert... " "$environment"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    if (keytool -import -alias server -trustcacerts -keystore "$keystore" -storepass "$STORE_PASS" -file "$signed_cert" 2>/dev/null); then
      # if the CA chain is not valid it will fail to import the cert. This is not the case when importing .p7b files, which will
      # blindly allow you to import but generate errors when used. Thus, why we are converting to PEM and importing each cert
      # individually
      echo " OK"
    else
      error_exit "Failed to import $signed_cert into $keystore. Exiting."
    fi
    rm "$signed_cert"
  )
}

get_vault_pass(){
  # if VAULT_PASS is set, use it
  [ -n "$VAULT_PASS" ] && return 0

  # else, prompt for it
  read -s -r -p "Enter Vault Password: " VAULT_PASS

  # make sure it's not empty
  [ -z "$VAULT_PASS" ] && error_exit "Please set vault pass"

  echo " OK"
}

encrypt_and_export_keystore(){
  local keystore="$1"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    echo "Exporting $keystore to $dst_dir..."
    ansible-vault encrypt "$keystore" --vault-password-file <(echo "$VAULT_PASS")
    
    # export.. make sure they want to overwrite if keystore exists
    if [[ "$force" == "true" ]]; then
      cp -f "$keystore" "$dst_dir"/"$keystore"
    else
      if [[ -f "$dst_dir"/"$keystore" ]]; then
        read -r -p "Overwrite $dst_dir/$keystore? [y/n] " response
        if [[ "$response" == "y" ]]; then
          cp -f "$keystore" "$dst_dir"/"$keystore"
        else
          error_exit "Aborting."
        fi
      fi
    fi
  )
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Parse command-line
while [[ -n $1 ]]; do
  # ignore -* | --* shellcheck complaints
  # shellcheck disable=SC2221 disable=SC2222
  case $1 in
    -h | --help) help_message; graceful_exit ;;
    -s | --source-dir)
      shift
      if [[ "$1" == "." ]]; then
        src_dir="$(pwd)"
      else
        src_dir="$1"
      fi
      if [[ ! -d "$src_dir" ]]; then
        error_exit "--source-dir is not valid."
      fi
    ;;
    -u | --update-ca-certs) download_certs=true ;;
    -e | --environment) shift; environments+=("$1") ;;
    -f | --force) force=true ;;
    -* | --*)
      usage
      error_exit "Unknown option $1" ;;
    *)
      if [[ -d "$1" ]]; then
        dst_dir="$1"
      else
        error_exit "$1 is not a valid directory."
      fi
    ;;
  esac
  shift
done

if [[ ${#environments[@]} -eq 0 ]]; then
  environments=("${default_environments[@]}")
fi

check_tools

# download CA root and intermediate certs
if [[ "$download_certs" == "true" ]]; then
  fetch_certs
fi

get_vault_pass
check_files

# ready to import
for e in "${environments[@]}"; do
  # copy our pristine keystores and signed tls cert to tmp
  cp "$src_dir/${e}_bfd_cms_gov.jks" "$tmp_dir"
  cp "$src_dir/${e}.bfd.cms.gov.pem" "$tmp_dir"

  # import root chain, certs, encrypt, and export
  import_root_chain "${e}_bfd_cms_gov.jks"
  import_signed_cert "$e" "${e}_bfd_cms_gov.jks" "${e}.bfd.cms.gov.pem"
  encrypt_and_export_keystore "${e}_bfd_cms_gov.jks"
done

graceful_exit
