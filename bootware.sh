#!/usr/bin/env bash
#
# Bootstrap software installations with Ansible.

# Exit immediately if a command exits or pipes a non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command pipeline fails.
#   -o: Persist nonzero exit codes through a Bash pipe.
#   -u: Throw an error when an unset variable is encountered.
set -eou pipefail

#######################################
# Show CLI help information.
# Cannot use function name help, since help is a pre-existing command.
# Outputs:
#   Writes help information to stdout.
#######################################
usage() {
  case "${1}" in
    bootstrap)
      cat 1>&2 << EOF
Boostrap install computer software

Usage: bootware bootstrap [OPTIONS]

Options:
      --check                     Perform dry run and show possible changes
      --checkout <REF>            Git reference to run against
  -c, --config <PATH>             Path to bootware user configuation file
      --debug                     Enable Ansible task debugger
  -d, --dev                       Run bootstrapping in development mode
  -h, --help                      Print help information
  -i, --inventory <IP-LIST>       Ansible host IP addesses
      --no-passwd                 Do not ask for user password
      --no-setup                  Skip Bootware dependency installation
      --password <PASSWORD>       Remote host user password
  -p, --playbook <FILE-NAME>      Path to playbook to execute
      --private-key <FILE-NAME>   Path to SSH private key
      --retries <INTEGER>         Playbook retry limit during failure
  -s, --skip <TAG-LIST>           Ansible playbook tags to skip
      --start-at-role <ROLE>      Begin execution with role
  -t, --tags <TAG-LIST>           Ansible playbook tags to select
      --temp-key <FILE-NAME>      Path to SSH private key for one time connection
  -u, --url <URL>                 URL of playbook repository
      --user <USER-NAME>          Remote host user login name
      --windows                   Connect to a Windows host with SSH

Ansible Options:
EOF
      ansible --help
      ;;
    config)
      cat 1>&2 << EOF
Download default Bootware configuration file

Usage: bootware config [OPTIONS]

Options:
  -d, --dest <PATH>     Path to alternate download destination
  -e, --empty           Write empty configuration file
  -h, --help            Print help information
  -s, --source <URL>    URL to configuration file
EOF
      ;;
    main)
      cat 1>&2 << EOF
Boostrapping software installer

Usage: bootware [OPTIONS] [SUBCOMMAND]

Options:
      --debug     Enable shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information

Subcommands:
  bootstrap   Boostrap install computer software
  config      Generate Bootware configuration file
  roles       List all Bootware roles
  setup       Install dependencies for Bootware
  uninstall   Remove Bootware files
  update      Update Bootware to latest version

Environment Variables:
  BOOTWARE_CONFIG     Set the configuration file path
  BOOTWARE_NOPASSWD   Assume passwordless sudo
  BOOTWARE_NOSETUP    Skip Ansible install and system setup
  BOOTWARE_PLAYBOOK   Set Ansible playbook name
  BOOTWARE_SKIP       Set skip tags for Ansible roles
  BOOTWARE_TAGS       Set tags for Ansible roles
  BOOTWARE_URL        Set location of Ansible repository

See 'bootware <subcommand> --help' for more information on a specific command.
EOF
      ;;
    roles)
      cat 1>&2 << EOF
List all Bootware roles

Usage: bootware roles [OPTIONS]

Options:
  -h, --help        Print help information
  -u, --url <URL>   URL of playbook repository
EOF
      ;;
    setup)
      cat 1>&2 << EOF
Install dependencies for Bootware

Usage: bootware setup [OPTIONS]

Options:
  -h, --help    Print help information
EOF
      ;;
    uninstall)
      cat 1>&2 << EOF
Remove Bootware files

Usage: bootware uninstall

Options:
  -h, --help    Print help information
EOF
      ;;
    update)
      cat 1>&2 << EOF
Update Bootware to latest version

Usage: bootware update [OPTIONS]

Options:
  -h, --help                Print help information
  -v, --version <VERSION>   Version override for update
EOF
      ;;
    *)
      error "No such usage option '${1}'"
      ;;
  esac
}

#######################################
# Assert that command can be found in system path.
# Will exit script with an error code if command is not in system path.
# Arguments:
#   Command to check availabilty.
# Outputs:
#   Writes error message to stderr if command is not in system path.
#######################################
assert_cmd() {
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v "${1}")" ]]; then
    error "Cannot find required ${1} command on computer"
  fi
}

#######################################
# Subcommand to bootstrap software installations.
# Globals:
#   BOOTWARE_CONFIG
#   BOOTWARE_NOPASSWD
#   BOOTWARE_NOSETUP
#   BOOTWARE_PLAYBOOK
#   BOOTWARE_SKIP
#   BOOTWARE_TAGS
#   BOOTWARE_URL
#   USER
#######################################
bootstrap() {
  # /dev/null is never a normal file.
  local ansible_config_path
  local ask_passwd
  local cmd='pull'
  local config_path="${BOOTWARE_CONFIG:-'/dev/null'}"
  local connection='local'
  local extra_args=()
  local inventory='127.0.0.1,'
  local no_setup="${BOOTWARE_NOSETUP:-}"
  local passwd
  local playbook
  local retries=1
  local skip="${BOOTWARE_SKIP:-}"
  local start_role
  local status
  local tags="${BOOTWARE_TAGS:-}"
  local temp_ssh_args=(
    "-o IdentitiesOnly=no"
    "-o LogLevel=ERROR"
    "-o StrictHostKeyChecking=no"
    "-o UserKnownHostsFile=/dev/null"
  )
  local url="${BOOTWARE_URL:-https://github.com/scruffaluff/bootware.git}"
  local windows

  # Check if Ansible should ask for user password.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [[ -z "${BOOTWARE_NOPASSWD:-}" ]]; then
    ask_passwd='true'
  fi

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      --ansible-config)
        export ANSIBLE_CONFIG="${2}"
        shift 2
        ;;
      -c | --config)
        config_path="${2}"
        shift 2
        ;;
      -d | --dev)
        cmd='playbook'
        playbook="${BOOTWARE_PLAYBOOK:-playbook.yaml}"
        shift 1
        ;;
      --debug)
        export ANSIBLE_ENABLE_TASK_DEBUGGER='True'
        shift 1
        ;;
      -h | --help)
        usage 'bootstrap'
        exit 0
        ;;
      -i | --inventory)
        cmd='playbook'
        connection='ssh'
        inventory="${2}"
        shift 2
        ;;
      --no-passwd)
        ask_passwd=''
        shift 1
        ;;
      --no-setup)
        no_setup='true'
        shift 1
        ;;
      -p | --playbook)
        playbook="${2}"
        shift 2
        ;;
      --password)
        passwd="${2}"
        shift 2
        ;;
      --retries)
        retries=${2}
        shift 2
        ;;
      -s | --skip)
        skip="${2}"
        shift 2
        ;;
      --start-at-role)
        start_role="${2}"
        cmd='playbook'
        shift 2
        ;;
      -t | --tags)
        tags="${2}"
        shift 2
        ;;
      --temp-key)
        extra_args+=(
          "--private-key"
          "${2}"
          "--ssh-extra-args"
          "${temp_ssh_args[*]}"
        )
        shift 2
        ;;
      -u | --url)
        url="${2}"
        shift 2
        ;;
      --windows)
        ask_passwd=''
        cmd='playbook'
        connection='ssh'
        windows='true'
        shift 1
        ;;
      *)
        extra_args+=("${1}")
        shift 1
        ;;
    esac
  done

  # Check if Bootware setup should be run.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [[ -z "${no_setup:-}" ]]; then
    setup
  fi

  # Download repository if no playbook is selected.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [[ "${cmd}" == 'playbook' && -z "${playbook:-}" ]]; then
    # Do not use long form --dry-run flag. It is not supported on MacOS.
    tmp_dir="$(mktemp -u)"
    git clone --depth 1 "${url}" "${tmp_dir}" &> /dev/null
    playbook="${tmp_dir}/playbook.yaml"
  fi

  # Find task associated with start role.
  #
  # Flags:
  #   -n: Check if the string has nonzero length.
  if [[ -n "${start_role:-}" ]]; then
    assert_cmd yq
    repo_dir="$(dirname "${playbook}")"
    start_task="$(
      yq '.[0].name' "${repo_dir}/ansible_collections/scruffaluff/bootware/roles/${start_role}/tasks/main.yaml"
    )"
    extra_args+=('--start-at-task' "${start_task}")
  fi

  # Convenience logic for using a single host without a trailing comma.
  if [[ ! "${inventory}" =~ .*','.* ]]; then
    inventory="${inventory},"
  fi

  if [[ "${cmd}" == 'playbook' ]]; then
    ansible_config_path="$(dirname "${playbook}")/ansible.cfg"
    if [[ -z "${ANSIBLE_CONFIG:-}" && -f "${ansible_config_path}" ]]; then
      export ANSIBLE_CONFIG="${ansible_config_path}"
    fi
    extra_args+=('--connection' "${connection}")
  elif [[ "${cmd}" == 'pull' ]]; then
    playbook="${BOOTWARE_PLAYBOOK:-playbook.yaml}"
    extra_args+=('--url' "${url}")
  fi

  find_config_path "${config_path}"
  config_path="${RET_VAL}"

  log "Executing Ansible ${cmd}"
  log 'Enter your user account password if prompted'

  until "ansible-${cmd}" \
    ${ask_passwd:+--ask-become-pass} \
    ${checkout:+--checkout "${checkout}"} \
    ${passwd:+--extra-vars "ansible_password=${passwd}"} \
    ${windows:+--extra-vars 'ansible_pkg_mgr=scoop'} \
    --extra-vars 'ansible_python_interpreter=auto_silent' \
    ${windows:+--extra-vars 'ansible_shell_type=powershell'} \
    --extra-vars "@${config_path}" \
    --inventory "${inventory}" \
    ${tags:+--tags "${tags}"} \
    ${skip:+--skip-tags "${skip}"} \
    ${extra_args:+"${extra_args[@]}"} \
    "${playbook}"; do

    status=$?
    ((retries--)) && ((retries == 0)) && exit "${status}"
    printf "\nBootstrapping attempt failed with exit code %s." "${status}"
    printf "\nRetrying bootstrapping with %s attempts left.\n" "${retries}"
    sleep 4
  done
}

#######################################
# Subcommand to generate or download Bootware configuration file.
# Globals:
#   HOME
# Arguments:
#   Parent directory of Bootware script.
# Outputs:
#   Writes status information to stdout.
#######################################
config() {
  local src_url dst_file="${HOME}/.bootware/config.yaml" empty_cfg

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -d | --dest)
        dst_file="${2}"
        shift 2
        ;;
      -e | --empty)
        empty_cfg='true'
        shift 1
        ;;
      -h | --help)
        usage 'config'
        exit 0
        ;;
      -s | --source)
        src_url="${2}"
        shift 2
        ;;
      *)
        error_usage "No such option '${1}'" "config"
        ;;
    esac
  done

  # Do not use long form --parents flag for mkdir. It is not supported on MacOS.
  mkdir -p "$(dirname "${dst_file}")"

  # Check if empty configuration file should be generated.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [[ "${empty_cfg:-}" == 'true' || -z "${src_url:-}" ]]; then
    log "Writing empty configuration file to ${dst_file}"
    printf 'passwordless_sudo: false' > "${dst_file}"
  else
    assert_cmd curl

    log "Downloading configuration file to ${dst_file}"

    # Download configuration file.
    #
    # FLAGS:
    #   -L: Follow redirect request.
    #   -S: Show errors.
    #   -f: Use archive file. Must be third flag.
    curl -LSfs "${src_url}" --output "${dst_file}"
  fi
}

#######################################
# Update dnf package lists.
#
# DNF's check-update command will give a 100 exit code if there are packages
# available to update. Thus both 0 and 100 must be treated as successful exit
# codes.
#
# Arguments:
#   Whether to use sudo command.
#######################################
dnf_check_update() {
  local code
  ${1:+sudo} dnf check-update || {
    code="$?"
    [[ "${code}" -eq 100 ]] && return 0
    return "${code}"
  }
}

#######################################
# Print error message and exit script with error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error() {
  local bold_red='\033[1;31m' default='\033[0m'
  printf "${bold_red}error${default}: %s\n" "${1}" >&2
  exit 1
}

#######################################
# Print error message and exit script with usage error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error_usage() {
  local bold_red='\033[1;31m' default='\033[0m'
  printf "${bold_red}error${default}: %s\n" "${1}" >&2
  printf "Run \'bootware %s--help\' for usage.\n" "${2:+${2} }" >&2
  exit 2
}

#######################################
# Find path of Bootware configuation file.
# Globals:
#   HOME
# Arguments:
#   User supplied configuration path.
# Outputs:
#   Writes error message to stderr if unable to find configuration file.
# Returns:
#   Configuration file path.
#######################################
find_config_path() {
  # Flags:
  #   -f: Check if file exists and is a regular file.
  #   -n: Check if the string has nonzero length.
  #   -v: Only show file path of command.
  if [[ -f "${1:-}" ]]; then
    RET_VAL="${1}"
  elif [[ -n "${BOOTWARE_CONFIG:-}" ]]; then
    RET_VAL="${BOOTWARE_CONFIG}"
  elif [[ -f "${HOME}/.bootware/config.yaml" ]]; then
    RET_VAL="${HOME}/.bootware/config.yaml"
  else
    log 'Unable to find Bootware configuation file.'
    config --empty
    RET_VAL="${HOME}/.bootware/config.yaml"
  fi

  log "Using ${RET_VAL} as configuration file"
}

#######################################
# Get full normalized path for file.
# Alternative to realpath command, since it is not built into MacOS.
#######################################
fullpath() {
  local working_dir

  # Flags:
  #   -P: Resolve any symbolic links in the path.
  working_dir="$(cd "$(dirname "${1}")" && pwd -P)"

  echo "${working_dir}/$(basename "${1}")"
}

#######################################
# Install YQ parser for YAML files.
# Arguments:
#   Whether to use sudo command.
#######################################
install_yq() {
  local arch os_type url version
  assert_cmd curl
  assert_cmd jq

  # Do not use long form --kernel-name or --machine flags for uname. They are
  # not supported on MacOS.
  arch="$(uname -m)"
  arch="${arch/#x86_64/amd64}"
  arch="${arch/%x64/amd64}"
  arch="${arch/#aarch64/arm64}"
  arch="${arch/%arm/arm64}"
  os_type="$(uname -s)"

  # Get latest YQ version.
  #
  # FLAGS:
  #   -L: Follow redirect request.
  #   -S: Show errors.
  #   -f: Fail silently on server errors.
  #   -o file: Save output to file.
  #   -s: Disable progress bars.
  version="$(
    curl -LSfs https://formulae.brew.sh/api/formula/yq.json |
      jq --exit-status --raw-output .versions.stable
  )"
  url="https://github.com/mikefarah/yq/releases/download/v${version}/yq_${os_type}_${arch}"

  # Do not quote the sudo parameter expansion. Bash will error due to be being
  # unable to find the "" command.
  ${1:+sudo} curl -LSfs "${url}" --output /usr/local/bin/yq
  ${1:+sudo} chmod 755 /usr/local/bin/yq
}

#######################################
# Print log message to stdout if logging is enabled.
# Globals:
#   BOOTWARE_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
log() {
  # Flags:
  #   -z: Check if string has zero length.
  if [[ -z "${BOOTWARE_NOLOG:-}" ]]; then
    echo "$@"
  fi
}

#######################################
# Subcommand to list all Bootware roles.
#######################################
roles() {
  local tmp_dir
  local url="${BOOTWARE_URL:-https://github.com/scruffaluff/bootware.git}"

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -h | --help)
        usage 'roles'
        exit 0
        ;;
      -u | --url)
        url="${2}"
        shift 2
        ;;
      *)
        error_usage "No such option '${1}'" "roles"
        ;;
    esac
  done

  # Do not use long form --dry-run flag for mktemp. It is not supported on
  # MacOS.
  tmp_dir="$(mktemp -u)"
  git clone --depth 1 "${url}" "${tmp_dir}" &> /dev/null
  ls -1 "${tmp_dir}/roles"
}

#######################################
# Subcommand to configure boostrapping services and utilities.
#######################################
setup() {
  local collections collection_status os_type tmp_dir use_sudo=''

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -h | --help)
        usage 'setup'
        exit 0
        ;;
      *)
        error_usage "No such option '${1}'" "setup"
        ;;
    esac
  done

  assert_cmd uname

  # Check if user is not root.
  if [[ "${EUID}" -ne 0 ]]; then
    use_sudo='true'
  fi

  # Do not use long form --kernel-name flag for uname. It is not supported on
  # MacOS.
  os_type="$(uname -s)"
  case "${os_type}" in
    Darwin)
      setup_macos
      ;;
    FreeBSD)
      setup_freebsd "${use_sudo}"
      ;;
    Linux)
      setup_linux "${use_sudo}"
      ;;
    *)
      error "Operating system ${os_type} is not supported"
      ;;
  esac

  collections=('chocolatey.chocolatey' 'community.general' 'community.windows')
  for collection in "${collections[@]}"; do
    collection_status="$(ansible-galaxy collection list "${collection}" 2>&1)"
    if [[ "${collection_status}" =~ 'unable to find' ]]; then
      ansible-galaxy collection install "${collection}"
    fi
  done
}

#######################################
# Configure boostrapping services and utilities for Alpine.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_alpine() {
  # Install dependencies for Bootware.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    ${1:+sudo} apk update
    ${1:+sudo} apk add ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    ${1:+sudo} apk update
    ${1:+sudo} apk add curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    ${1:+sudo} apk update
    ${1:+sudo} apk add git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    ${1:+sudo} apk update
    ${1:+sudo} apk add jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Configure boostrapping services and utilities for Arch.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_arch() {
  local tmp_dir

  # Install dependencies for Bootware.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    # Installing Ansible via Python causes pacman conflicts with AWSCLI.
    ${1:+sudo} pacman --noconfirm --refresh --sync --sysupgrade
    ${1:+sudo} pacman --noconfirm --sync ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    ${1:+sudo} pacman --noconfirm --refresh --sync --sysupgrade
    ${1:+sudo} pacman --noconfirm --sync curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    ${1:+sudo} pacman --noconfirm --refresh --sync --sysupgrade
    ${1:+sudo} pacman --noconfirm --sync git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    ${1:+sudo} pacman --noconfirm --refresh --sync --sysupgrade
    ${1:+sudo} pacman --noconfirm --sync jq
  fi

  if [[ ! -x "$(command -v yay)" ]]; then
    log 'Installing Yay package manager'
    ${1:+sudo} pacman --noconfirm --refresh --sync --sysupgrade
    ${1:+sudo} pacman --noconfirm --sync base-devel

    tmp_dir="$(mktemp --dry-run)"
    git clone --depth 1 'https://aur.archlinux.org/yay.git' "${tmp_dir}"
    (cd "${tmp_dir}" && makepkg --install --noconfirm --syncdeps)
    yay --noconfirm --refresh --sync --sysupgrade
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Configure boostrapping services and utilities for Debian.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_debian() {
  # Avoid APT interactively requesting to configure tzdata.
  export DEBIAN_FRONTEND='noninteractive'

  # Install dependencies for Bootware.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v ansible)" ]]; then
    # Install Ansible with Python3 since most package managers provide an old
    # version of Ansible.
    log 'Installing Ansible'
    ${1:+sudo} apt-get --quiet update
    ${1:+sudo} apt-get --quiet install --yes ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    ${1:+sudo} apt-get --quiet update
    ${1:+sudo} apt-get --quiet install --yes curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    ${1:+sudo} apt-get --quiet update
    ${1:+sudo} apt-get --quiet install --yes git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    ${1:+sudo} apt-get --quiet update
    ${1:+sudo} apt-get --quiet install --yes jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Configure boostrapping services and utilities for Fedora.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_fedora() {
  # Install dependencies for Bootware.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    # Installing Ansible via Python causes issues installing remote DNF packages
    # with Ansible.
    dnf_check_update "${1}"
    ${1:+sudo} dnf install --assumeyes ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    dnf_check_update "${1}"
    ${1:+sudo} dnf install --assumeyes curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    dnf_check_update "${1}"
    ${1:+sudo} dnf install --assumeyes git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    dnf_check_update "${1}"
    ${1:+sudo} dnf install --assumeyes jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Configure boostrapping services and utilities for FreeBSD.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_freebsd() {
  assert_cmd pkg python_version

  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    # Install Ansible with Python3 since most package managers provide an old
    # version of Ansible.
    ${1:+sudo} pkg update
    # Python's cryptography package requires a Rust compiler on FreeBSD.
    ${1:+sudo} pkg install --yes python3 rust

    python_version="$(
      python3 -c 'import sys; print("{}{}".format(*sys.version_info[:2]))'
    )"
    ${1:+sudo} pkg install --yes "py${python_version}-pip"

    ${1:+sudo} python3 -m pip install --upgrade pip setuptools wheel
    ${1:+sudo} python3 -m pip install ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    ${1:+sudo} pkg update
    ${1:+sudo} pkg install --yes curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    ${1:+sudo} pkg update
    ${1:+sudo} pkg install --yes git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    ${1:+sudo} pkg update
    ${1:+sudo} pkg install --yes jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Configure boostrapping services and utilities for Linux.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_linux() {
  # Install dependencies for Bootware base on available package manager.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ -x "$(command -v apk)" ]]; then
    setup_alpine "${1}"
  elif [[ -x "$(command -v pacman)" ]]; then
    setup_arch "${1}"
  elif [[ -x "$(command -v apt-get)" ]]; then
    setup_debian "${1}"
  elif [[ -x "$(command -v dnf)" ]]; then
    setup_fedora "${1}"
  elif [[ -x "$(command -v zypper)" ]]; then
    setup_suse "${1}"
  else
    error 'Unable to find supported package manager'
  fi
}

#######################################
# Configure boostrapping services and utilities for MacOS.
#######################################
setup_macos() {
  assert_cmd curl

  # On Apple silicon, brew is not in the system path after installation.
  export PATH="/opt/homebrew/bin:${PATH}"

  # Install XCode command line tools if not already installed.
  #
  # Homebrew depends on the XCode command line tools.
  # Flags:
  #   -p: Print path to active developer directory.
  if ! xcode-select -p &> /dev/null; then
    log 'Installing command line tools for XCode'
    sudo xcode-select --install
  fi

  # Install Rosetta 2 for Apple Silicon if not already installed.
  #
  # # Do not use long form --processor flag for uname. It is not supported on
  # MacOS.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  if [[ "$(uname -p)" == 'arm' && ! -d '/opt/homebrew' ]]; then
    softwareupdate --agree-to-license --install-rosetta
  fi

  # Install Homebrew if not already installed.
  #
  # FLAGS:
  #   -L: Follow redirect request.
  #   -S: Show errors.
  #   -f: Fail silently on server errors.
  #   -s: Disable progress bars.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v brew)" ]]; then
    log 'Installing Homebrew'
    curl -LSfs 'https://raw.githubusercontent.com/Homebrew/install/master/install.sh' | bash
  fi

  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    brew install ansible
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    brew install git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    brew install jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    brew install yq
  fi
}

#######################################
# Configure boostrapping services and utilities for OpenSuse.
# Arguments:
#   Whether to use sudo command.
#######################################
setup_suse() {
  # Install dependencies for Bootware.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [[ ! -x "$(command -v ansible)" ]]; then
    log 'Installing Ansible'
    ${1:+sudo} zypper update --no-confirm
    ${1:+sudo} zypper install --no-confirm python3 python3-pip

    ${1:+sudo} python3 -m pip install --upgrade pip setuptools wheel
    ${1:+sudo} python3 -m pip install ansible
  fi

  if [[ ! -x "$(command -v curl)" ]]; then
    log 'Installing Curl'
    ${1:+sudo} zypper update --no-confirm
    ${1:+sudo} zypper install --no-confirm curl
  fi

  if [[ ! -x "$(command -v git)" ]]; then
    log 'Installing Git'
    ${1:+sudo} zypper update --no-confirm
    ${1:+sudo} zypper install --no-confirm git
  fi

  if [[ ! -x "$(command -v jq)" ]]; then
    log 'Installing JQ'
    ${1:+sudo} zypper update --no-confirm
    ${1:+sudo} zypper install --no-confirm jq
  fi

  if [[ ! -x "$(command -v yq)" ]]; then
    log 'Installing YQ'
    install_yq "${1}"
  fi
}

#######################################
# Subcommand to remove Bootware files.
# Outputs:
#   Writes status information about removed files.
#######################################
uninstall() {
  local dst_file use_sudo=''

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -h | --help)
        usage 'uninstall'
        exit 0
        ;;
      *)
        error_usage "No such option '${1}'" "update"
        ;;
    esac
  done

  assert_cmd chmod

  dst_file="$(fullpath "$0")"

  # Use sudo for system installation if user is not root.
  #
  # Flags:
  #   -w: Check if file exists and it writable.
  if [[ ! -w "${dst_file}" && "${EUID}" -ne 0 ]]; then
    assert_cmd sudo
    use_sudo='true'
  fi

  # Do not quote the sudo parameter expansion. Bash will error due to be being
  # unable to find the "" command.
  ${use_sudo:+sudo} rm "${dst_file}"

  log 'Uninstalled Bootware'
}

#######################################
# Subcommand to update Bootware script.
# Arguments:
#   Parent directory of Bootware script.
# Outputs:
#   Writes status information and updated Bootware version to stdout.
#######################################
update() {
  local dst_file src_url use_sudo='' user_install version='main'

  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      -h | --help)
        usage 'update'
        exit 0
        ;;
      -v | --version)
        version="${2}"
        shift 2
        ;;
      *)
        error_usage "No such option '${1}'" "update"
        ;;
    esac
  done

  assert_cmd chmod
  assert_cmd curl

  dst_file="$(fullpath "$0")"
  src_url="https://raw.githubusercontent.com/scruffaluff/bootware/${version}/bootware.sh"

  # Use sudo for system installation if user is not root.
  #
  # Flags:
  #   -w: Check if file exists and it writable.
  if [[ ! -w "${dst_file}" && "${EUID}" -ne 0 ]]; then
    assert_cmd sudo
    use_sudo='true'
  elif [[ -w "${dst_file}" && "${EUID}" -ne 0 ]]; then
    user_install='true'
  fi

  log 'Updating Bootware'

  # Do not quote the sudo parameter expansion. Bash will error due to be being
  # unable to find the "" command.
  ${use_sudo:+sudo} curl -LSfs "${src_url}" --output "${dst_file}"
  ${use_sudo:+sudo} chmod 755 "${dst_file}"

  update_completions "${use_sudo}" "${user_install:-}" "${version}"
  log "Updated to version $(bootware --version)"
}

#######################################
# Update completion scripts for Bootware.
# Arguments:
#   Whether to use sudo for installation.
#   Whether to install for entire system.
#   GitHub version reference.
#######################################
update_completions() {
  local repo_url="https://raw.githubusercontent.com/scruffaluff/bootware/${3}"
  local bash_url="${repo_url}/completions/bootware.bash"
  local fish_url="${repo_url}/completions/bootware.fish"

  # Flags:
  #   -z: Check if the string has zero length or is null.
  if [[ -z "${2:-}" ]]; then
    # Do not use long form --parents flag for mkdir. It is not supported on
    # MacOS.
    ${1:+sudo} mkdir -p '/etc/bash_completion.d'
    ${1:+sudo} curl -LSfs "${bash_url}" -o '/etc/bash_completion.d/bootware.bash'
    ${1:+sudo} chmod 664 '/etc/bash_completion.d/bootware.bash'

    ${1:+sudo} mkdir -p '/etc/fish/completions'
    ${1:+sudo} curl -LSfs "${fish_url}" -o '/etc/fish/completions/bootware.fish'
    ${1:+sudo} chmod 664 '/etc/fish/completions/bootware.fish'
  else
    mkdir -p "${HOME}/.config/fish/completions"
    curl -LSfs "${fish_url}" -o "${HOME}/.config/fish/completions/bootware.fish"
    chmod 664 "${HOME}/.config/fish/completions/bootware.fish"
  fi
}

#######################################
# Print Bootware version string.
# Outputs:
#   Bootware version string.
#######################################
version() {
  echo 'Bootware 0.6.1'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Parse command line arguments.
  while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage 'main'
        exit 0
        ;;
      -v | --version)
        version
        exit 0
        ;;
      bootstrap)
        shift 1
        bootstrap "$@"
        exit 0
        ;;
      config)
        shift 1
        config "$@"
        exit 0
        ;;
      roles)
        shift 1
        roles "$@"
        exit 0
        ;;
      setup)
        shift 1
        setup "$@"
        exit 0
        ;;
      uninstall)
        shift 1
        uninstall "$@"
        exit 0
        ;;
      update)
        shift 1
        update "$@"
        exit 0
        ;;
      *)
        error_usage "No such subcommand or option '${1}'"
        ;;
    esac
  done
}

# Only run main if invoked as script. Otherwise import functions as library.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
