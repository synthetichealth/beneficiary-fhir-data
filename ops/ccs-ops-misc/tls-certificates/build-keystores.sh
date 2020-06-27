#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-keystores.sh - Installs and encrypts BFD Java keystores. This script
# can be run manually if needed, but should be plugged into CI/CD to ensure
# our TLS certificates are valid and up to date.
#
# Usage:
#     build-keystores.sh -h
# ---------------------------------------------------------------------------
PROGNAME=${0##*/}

# Store and key passwords. These default to 'changeit', but you can overide by setting and exporting
# 'STORE_PASS' or 'KEY_PASS' environment variables.
STORE_PASS="${STORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
VAULT_PASS="${VAULT_PASS:-}"

# URL's to any root/intermediate certificates used to sign our certificates
root="https://ocio.nih.gov/Smartcard/Documents/Certificates/Entrust_Root_CA-G2.cer"
intermediate="https://ocio.nih.gov/Smartcard/Documents/Certificates/Entrust_CA-L1k.cer"
ca_cert_alias=(root intermediate)
ca_cert_urls=("$root" "$intermediate")

# When the --update-ca-certs flag is present, we download the CA chain certificates from nih.gov, and 
# rename them to be a bit more script friendly.
ca_certs=("entrust_root_ca_g2.pem" "entrust_ca_l1k.pem")

# program variables
tmp_dir=$(mktemp -d -t bfd-certs-XXXXXXXXXX)
dst_dir="${dst_dir:-$(pwd)}"
dst_dir="${dst_dir%/}" # remove trailing slash
src_dir=
environments=()
default_environments=(prod prod-sbx test)
downloaded_ca_certs=false
force=false

# Perform pre-exit housekeeping
clean_up() {
  rm -rf "$tmp_dir" >/dev/null 2>&1
}

error_exit() {
  echo
  echo -e "$1" >&2
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
      error_exit "Bailing out." ;;
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
  $PROGNAME - Builds and encrypts our BFD Java keystores with the full TLS certificate chain installed.
  - Downloads CA root certificate chain (if --update-ca-certs is set)
  - Installs the root CA chain used to sign our certificate
  - Installs and validates the signed cert
  - Encrypts and exports the keystore to the <destination directory>
  
  $(usage)

  Examples:
    # Build all environments keystores (prod, prod-sbx, and test) and export to ~/Desktop/foo.
    mkdir -p ~/Desktop/foo
    ./$PROGNAME --source-dir /path/to/Keybase/dir ~/Desktop/foo

    # Build test and prod-sbx keystores and do not prompt to overwrite any existing files.
    ./$PROGNAME --source-dir /path/to/Keybase/dir -e test -e prod-sbx --force ~/Desktop/foo

    # Download CA certs from the internet and export keystores in preparation for a deployment.
    ./$PROGNAME --update-ca-certs --source-dir /Volumes/Keybase/path/to/bfd/keys ../../ansible/playbooks-ccs/files

  Options:
  -h, --help  Display this help message and exit.
  -s, --source-dir path  [Required] Source directory containing our pristine keystores and signed certs.
    Where 'path' is the Path to source directory. This could be /Volumes/Keybase/.... And 'pristine' meaning that 
    the source keystores only contain the private key
  [-u, --update-ca-certs]  Download root and intermediate CA certificates.
  [-e, --environment name]  Specify one or more environment(s) to process by setting one or more '-e' flags.
    Where 'name' is the Name of an environment. E.g., '-e prod -e prod-sbx'. Defaults to all environments.
  [-f, --force] Do not prompt for user input. This will overwrite any existing files.

_EOF_
  return
}


# ensures we have 'openssl' and 'keytool' installed. Also verifies we are not using the default MacOS openssl
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

  # CA certs should all be in the $tmp_dir by now.. verify we have them all
  for ca_cert in "${ca_certs[@]}"; do
    [ ! -f "$tmp_dir"/"$ca_cert" ] && missing_files+=("$ca_cert")
  done
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing one or more CA certificates in the source directory:"
    for f in "${missing_files[@]}"; do
      echo "  - $f"
    done
    echo "Maybe run with '--update-ca-certs' option to download them first."
    error_exit "Exiting."
  fi
  
  # check for keystores and signed certificates
  missing_files=()
  for environment in "${environments[@]}"; do
    [ ! -f "${src_dir}/${environment}_bfd_cms_gov.jks" ] && missing_files+=("${environment}_bfd_cms_gov.jks")
    [ ! -f "${src_dir}/${environment}.bfd.cms.gov.pem" ] && missing_files+=("${environment}.bfd.cms.gov.pem")
  done
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing keystores and/or signed certificates in $src_dir:"
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
      error_exit "Bailing out."
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

# import root chain
import_root_chain(){
  local keystore="$1"
  printf "Importing root chain"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    local cert_index=0
    for ca_cert in "${ca_certs[@]}"; do
      keytool -importcert -noprompt -alias "${ca_cert_alias[cert_index]}" -trustcacerts -keystore "$keystore" -storepass "$STORE_PASS" -file "$ca_cert" 2>/dev/null
      printf "."
      cert_index+=1
    done
  )
  echo " OK"
}

import_signed_cert(){
  local environment="$1"
  local keystore="$2"
  local signed_cert="$3"
  printf "Importing signed cert... "
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

# TODO: remove this.
# Import entries from our old keystores to handle the old domains until everyone is moved over.
# Once everyone is moved over, we can simply remove this from the build process.
import_old(){
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    local environment="$1"
    local keystore="$2"
    local partners=(mct dpc bcda bb ab2d)

    printf "Generating self-signed certs for bfdcloud domain..."
    # build a list of our subject alternate names to pass as -ext arg to keytool
    ext="san=dns:${environment}.bfdcloud.net"

    # partner domains
    for partner in "${partners[@]}"; do
      ext+=",dns:${partner}.${environment}.bfdcloud.net"
    done

    # not sure if these are still in use, adding them because they were in the existing certs
    case "$environment" in
      prod)
        ext+=",dns:internal-pdcw10lb01-1951212262.us-east-1.elb.amazonaws.com"
      ;;
      prod-sbx)
        ext+=",dns:internal-dpcwelb01-2074070868.us-east-1.elb.amazonaws.com"
        ext+=",dns:fhir.backend.bluebutton.hhsdevcloud.us"
      ;;
      test)
        ext+=",dns:internal-tsbb10lb01-758855236.us-east-1.elb.amazonaws.com"
      ;;
    esac
    
    # generate the self-signed certs and add to our keystore under the "self-signed" alias
    (keytool -genkeypair -alias "self-signed" -keyalg RSA -keysize 4096 \
        -dname "cn=${environment}.bfdcloud.net" \
        -ext "$ext" \
        -validity 730 -keypass changeit -keystore "${environment}_bfd_cms_gov.jks" -storepass changeit 2>/dev/null)
    echo " OK"
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


export_public_certs(){
  local environment="$1"
  local keystore="$2"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    
    # extract *.bfd.cms.gov public cert
    (keytool -export -keystore "${keystore}" -alias "server" -storepass changeit -file "${environment}.bfd.cms.gov.public.pem" -rfc 2>/dev/null)
    local dst_file="${dst_dir}/${environment}.bfd.cms.gov.public.pem"
    if [[ -f $dst_file ]]; then
      read -r -p "Overwrite ${environment}.bfd.cms.gov.public.pem? [y/n] " response
      if [[ "$response" == "y" ]]; then
        cp -f  "${environment}.bfd.cms.gov.public.pem" "$dst_file"
      else
        error_exit "Bailing out."
      fi
    else
      cp "${environment}.bfd.cms.gov.public.pem" "$dst_file"
    fi

    # extract the bfddcloud self-signed public cert
    local dst_file="${dst_dir}/${environment}.bfdcloud.net.public.pem"
    (keytool -export -keystore "${keystore}" -alias "self-signed" -storepass changeit -file "${environment}.bfdcloud.net.public.pem" -rfc 2>/dev/null)
    if [[ -f $dst_file ]]; then
      read -r -p "Overwrite ${environment}.bfdcloud.net.public.pem? [y/n] " response
      if [[ "$response" == "y" ]]; then
        cp -f  "${environment}.bfdcloud.net.public.pem" "$dst_file"
      else
        error_exit "Bailing out."
      fi
    else
      cp "${environment}.bfdcloud.net.public.pem" "$dst_file"
    fi
  )
}

encrypt_and_export_keystore(){
  local keystore="$1"
  (
    cd "$tmp_dir" || error_exit "Could not cd into $tmp_dir"
    printf "Encrypting keystore..."
    (ansible-vault encrypt "$keystore" --vault-password-file <(echo "$VAULT_PASS") >/dev/null 2>&1 )
    echo " OK"

    # export.. make sure they want to overwrite if keystore exists
    echo "Exporting $keystore"
    if [[ "$force" == "true" ]]; then
      cp -f "$keystore" "$dst_dir"/"$keystore"
    else
      if [[ -f "$dst_dir"/"$keystore" ]]; then
        read -r -p "Overwrite $dst_dir/$keystore? [y/n] " response
        if [[ "$response" == "y" ]]; then
          cp -f "$keystore" "$dst_dir"/"$keystore"
        else
          error_exit "Bailing out."
        fi
      else
        cp "$keystore" "$dst_dir"/"$keystore"
      fi
    fi
    echo "Successfully built, encrypted and exported $keystore to $dst_dir"
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

# --- MAIN PROGRAM LOGIC BELOW ---
check_tools
get_vault_pass

# set environments and prepare files
if [[ ${#environments[@]} -eq 0 ]]; then
  environments=("${default_environments[@]}")
fi

# download CA root and intermediate certs if selected
if [[ "$download_certs" == "true" ]]; then
  fetch_certs
fi
check_files

# import, build, encrypt, and export the keystore
for e in "${environments[@]}"; do
  echo
  echo "---- BUILDING ${e^^} KEYSTORE----"
  # copy our keystores and signed certs to tmp
  cp "$src_dir/${e}_bfd_cms_gov.jks" "$tmp_dir"
  cp "$src_dir/${e}.bfd.cms.gov.pem" "$tmp_dir"

  # import our CA root chain into the keystore
  import_root_chain "${e}_bfd_cms_gov.jks" || break

  # Import the signed cert
  import_signed_cert "$e" "${e}_bfd_cms_gov.jks" "${e}.bfd.cms.gov.pem" || break

  # import_old "$e" "${e}_bfd_cms_gov.jks"

  # export public certs
  # export_public_certs "$e" "${e}_bfd_cms_gov.jks"
  
  # encrypt and export
  encrypt_and_export_keystore "${e}_bfd_cms_gov.jks" || break
done

graceful_exit
