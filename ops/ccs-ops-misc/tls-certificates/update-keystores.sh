#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# update-keystores.sh - Installs and verifies TLS certificates in our keystores. Encrypts with ansible-vault.
#
# Usage: 
#   update-keystores.sh [-h|--help] [-d|--update-ca-certs] [-e|--environment name] [-s|--source-dir path] [-c|--check-dates] <output directory>
#
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}

# Store and key passwords. These default to 'changeit', but you can overide by setting and exporting
# 'STORE_PASS' or 'KEY_PASS' environment variables.
STORE_PASS="${STORE_PASS:-changeit}"
KEY_PASS="${KEY_PASS:-changeit}"
VAULT_PASS="${VAULT_PASS:-}"

# hard-coded list of partners
partners=(mct dpc bcda bb ab2d)

# URL's to the CA certs that was used to sign our certificates
fed_root="https://ocio.nih.gov/Smartcard/Documents/Certificates/Federal_CP_Root_SHA256.cer"
entrust_root="https://ocio.nih.gov/Smartcard/Documents/Entrust%20Managed%20Services%20Root%20CA.cer"
intermediate="https://ocio.nih.gov/Smartcard/Documents/HHS-FPKI-Intermediate.cer"
ca_cert_urls=($fed_root $entrust_root $intermediate)

# ca_cert_chain - An array of containing each CA root/intermediate certificate chain IN ORDER. 
# the --update-ca-certs option downloads the chain using the url's above. WE also convert the chain
# to PEM format and rename to make script friendly.
ca_certs=(federal_cp_root_sha256.pem entrust_managed_services_root_ca.pem hhs_fpki_intermediate.pem)


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
  rm -rf "${tmp_dir}"
}

error_exit() {
  echo -e "$1" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  echo "$1"
  exit
}

# Handle trapped signals
signal_exit() {
  case $1 in
    INT)
      error_exit "Stopping." ;;
    TERM)
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}


usage() {
  echo -e "Usage: $PROGNAME -s|--source-dir /path/to/certs/dir [-h|--help] [-u|--update-ca-certs] [-e|--environment name] [-c|--check-dates] [-f|--force] [<destination directory>]"
}

help_message() {
  cat <<- _EOF_
  $PROGNAME
  Installs BFD's CA root, intermediate, and signed TLS certificates into our keystores.
  Encrypts with ansible-vault and exports to the <destination directory> which defaults
  to the current directory if not supplied. This tool can also be used to download needed
  CA certificates, check expiration dates (TODO), and rotate certificates (TODO).

  $(usage)

  Examples:
    # Build keystore for the test environment and output to current working directory.
    ./$PROGNAME --update-ca-certs -e test -s /path/to/Keybase/dir ../ansible/playbooks-ccs/files

    # Builds keystores for all environments and exports them to your Desktop
    ./$PROGNAME -s /path/to/Keybase/dir ~/Desktop

  Options:
  -h, --help  Display this help message and exit.
  -s, --source-dir path  [Required] Source directory containing our keystores and signed certs.
    Where 'path' is the Path to source directory. This could be /Volumes/Keybase/....
  [-u, --update-ca-certs]  Download root and intermediate CA certificates.
  [-e, --environment name]  Specify environment(s). I.e. '-e prod-sbx -e prod'. Defaults to all.
    Where 'name' is the Name of the environment. E.g., prod prod-sbx or test.
  [-c, --check-dates]  Check certificate dates.
  [-f, --force] Do not prompt to overwrite existing files.

_EOF_
  return
}


# ensures we have openssl and keytool installed and makes sure we are not using the default MacOS openssl
check_tools(){
  # keytool
  (command -v keytool >/dev/null 2>&1) || error_exit "Missing 'keytool' command. Please install Java."

  # openssl
  (command -v openssl >/dev/null 2>&1) || error_exit "You need openssl installed to run this script."
  if [[ "$(openssl version)" =~ "LibreSSL" ]]; then
    error_exit "LibreSSL based openssl is incompatible with our keystores. Please `brew install openssl`\
    follow the directions to add to your PATH"
  fi
}

# ensures we have access to our keystores and certificates
check_files(){
  local missing_files=()
  local ca_in_src=false
  local ca_src_dir=

  # CA certificates
  if [[ "${downloaded_ca_certs}" == "true" ]]; then
    ca_src_dir=$tmp_dir
  else
    ca_src_dir=$src_dir
  fi

  for ca_cert in "${ca_certs[@]}"; do
    [ ! -f $ca_src_dir/$ca_cert ] && missing_files+=("${ca_cert}")
  done

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing one or more CA certificates in the source directory:"
    for f in "${missing_files[@]}"; do
      echo "  - ${f}"
    done
    echo "Maybe run with '--update-ca-certs' option to download them."
    error_exit "Exiting."
  fi
  missing_files=()

  # access to keystores and signed certificates
  for environment in "${environments[@]}"; do
    [ ! -f "${src_dir}/${environment}_bfd_cms_gov.jks" ] && missing_files+=("${environment}_bfd_cms_gov.jks")
    [ ! -f "${src_dir}/${environment}.bfd.cms.gov.pem" ] && missing_files+=("${environment}.bfd.cms.gov.pem")
  done

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "Missing some keystores or certificates in the source directory:"
    for f in "${missing_files[@]}"; do
      echo "  - ${f}"
    done
    error_exit "Exiting."
  fi
}

check_dates(){
  graceful_exit "Checking dates not implemented yet."
}

fetch_certs(){
  local ca_exists=false
  for cer in "${ca_certs[@]}"; do
    [[ -f $src_dir/$cer ]] && ca_exists=true
    [[ -f $dst_dir/$cer ]] && ca_exists=true
  done

  if [[ "$force" == "false" ]] && [[ "$ca_exists" == "true" ]]; then
    read -r -p "Overwrite existing CA certs in source directory? [y/n] " response
    if [[ ! "$response" == "y" ]]; then
      error_exit "Aborting."
    fi
  fi

  printf "Downloading CA certificates"
  for ca_url in "${ca_cert_urls[@]}"; do
    (cd "${tmp_dir}"; curl -O "${ca_url}" >/dev/null 2>&1) || error_exit "Failed to download CA certifcate from ${ca_url}"
    printf "."
  done
  echo " OK"

  # convert from DER to PEM and cleanup the file names
  printf "Preparing CA certificates"
  (
    cd $tmp_dir
    for cer in *.cer; do
      openssl x509 -in "$cer" -inform DER > "${cer%%.*}.tmp"
    done
  )

  # export
  (
    cd $tmp_dir
    for p in *.tmp; do
      local lower="${p,,}"                      # convert to lower case
      local fix_spaces="${lower//%20/_}"        # replace %20 with _
      local underscores="${fix_spaces// /_}"    # replace spaces with underscores
      local dashes="${underscores//-/_}"        # replace dashes with underscores
      local pem="${dashes%%.*}.pem"             # rename
      cp -f $p $tmp_dir/$pem                    # copy to our tmp working directory
      printf "."
    done
  )
  downloaded_ca_certs=true
  echo " OK"
}

validate_keystore(){
  local keystore="$1"
  #keytool -list -v -keystore test_bfd_cms_gov.jks -storepass changeit -alias server 2>/dev/null | grep Valid\ from | awk '{ print $12"-"$11"-"$15}'
}

# import certs, export, and encrypt
import_root_chain(){
  local keystore="$1"
  printf "Importing root chain into $keystore"
  (
    cd $tmp_dir
    
    # import the CA chain in order
    for ca_cert in "${ca_certs[@]}"; do
      keytool -importcert -noprompt -alias "${ca_cert}" -trustcacerts -keystore "${keystore}" -storepass "${STORE_PASS}" -file "${ca_cert}" 2>/dev/null
      printf "."
      rm $ca_cert
    done
  )
  echo " OK"
}

import_signed_cert(){
  local keystore="$1"
  local signed_cert="$2"
  printf "Importing $2 into $1 "
  (
    cd $tmp_dir
    keytool -import -alias server -trustcacerts -keystore "${keystore}" -storepass "${STORE_PASS}" -file "${2}" 2>/dev/null
    if [[ ! $? -eq 0 ]]; then
      echo "Failed to import $signed_cert into the $keystore."
      error_exit $result
    fi
    rm "$2"
    echo "OK"
  )
}


# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Parse command-line
while [[ -n $1 ]]; do
  case "$1" in
    -h | --help) help_message; graceful_exit ;;
    -s | --source-dir)
      shift
      if [[ "$1" == "." ]]; then
        src_dir="$(pwd)"
      else
        src_dir="${1}"
      fi
      if [[ ! -d $src_dir ]]; then
        error_exit "--source-dir is not valid."
      fi
      ;;
    -u | --update-ca-certs) download_certs=true ;;
    -e | --environment) shift; environments+=("$1") ;;
    -c | --check-dates) check_dates=true ;;
    -f | --force) force=true ;;
    -* | --*)
      usage
      error_exit "Unknown option $1" ;;
    *)
      if [[ -d "$1" ]]; then
        dst_dir="$1"
      else
        error_exit "${1} is not a valid directory."
      fi
      ;;
  esac
  shift
done

if [[ ${#environments[@]} -eq 0 ]]; then
  environments=$default_environments
fi

check_tools

# download CA root and intermediate certs
if [[ "${download_certs}" == "true" ]]; then
  fetch_certs
fi

check_files


# ready to import
for e in "${environments[@]}"; do
  # copy out pristine keystores and signed tls cert to tmp
  cp "${src_dir}/${e}_bfd_cms_gov.jks" $tmp_dir
  cp "${src_dir}/${e}.bfd.cms.gov.pem" $tmp_dir

  # import certs, test, encrypt, and export
  import_root_chain "${e}_bfd_cms_gov.jks"
  import_signed_cert "${e}_bfd_cms_gov.jks" "${e}.bfd.cms.gov.pem"
  validate_keystore "${e}_bfd_cms_gov.jks"
  # export_pub_certs
  # encrypt_keystore ${e}
done

# export artifacts
cp $tmp_dir/*.jks "${dst_dir}/"
# cp $tmp_dir/*.pem "${dst_dir}/"


graceful_exit
