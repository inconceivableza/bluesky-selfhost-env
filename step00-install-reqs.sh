#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] [--no-android] [--no-sudo]"
}

function show_help() {
  echo "Usage: $0 [-?|-h|--help] []"
  echo
  echo "Install requirements for bluesky-selfhost-env"
  echo
  echo "Options:"
  echo "  --no-sudo            don't run any commands that require sudo; simply output them"
  echo "  --no-android         don't install android build components"
  echo
}

do_android=1
do_sudo=1
while [ $# -gt 0 ]
  do
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_help >&2 ; exit ; }
    [[ "$1" == "--no-android" ]] && { do_android=0 ; shift 1 ; continue; }
    [[ "$1" == "--no-sudo" ]] && { do_sudo=0 ; shift 1 ; continue; }
    [[ "${1#-}" != "$1" ]] && {
      show_error "Unknown parameter" "$1"
      show_usage >&2
      exit 1
    }
    show_error "Unknown parameter" "$1"
    show_usage >&2
    exit 1
  done

function exec_sudo() {
  if [ "$do_sudo" == 1 ]; then
    sudo "$@"
  else
    show_info --oneline "sudo command required but --no-sudo given" "please run the following command manually:"
    echo "sudo $@"
  fi
}

if ! which docker >/dev/null
  then
    show_error --oneline "Docker install required" "in order to use this self-hosting environment"
    show_info --oneline "Please install docker manually" "by following the docker installation instructions"
    exit 1
  fi

if [ "$os" == "linux-ubuntu" ]
  then
    show_heading "Setting up apt packages" that are requirements for building running and testing these docker images
    # make is used to run setup scripts etc
    # pwgen is used to generate new securish passwords
    # jq in are used in extracting json data for config and tests
    apt_packages="make pwgen jq json5"

    if dpkg-query -l $apt_packages
      then
        show_info "No install required:" all packages already installed
      else
        exec_sudo apt update
        exec_sudo apt install -y $apt_packages
      fi

    show_heading "Setting up snap packages" that are requirements for building running and testing these docker images
    # yq is used in extracting yaml data for config and tests; the current ubuntu apt package is 3.x, but we want 4.x
    snap_packages="yq go"
    old_apt_packages="yq"
    if dpkg-query -l $old_apt_packages
      then
        show_warning "Old version of $old_apt_packages found" "installed using apt; will remove and install snap version"
        exec_sudo apt remove $old_apt_packages
    fi
    if snap list $snap_packages
      then
        show_info "No install required:" all packages already installed
      else
        exec_sudo snap install $snap_packages
      fi
    
    show_heading "Setting up websocat" directly from executable download, in /usr/local/bin
    if [ -x /usr/local/bin/websocat ] && websocat --version
      then
        show_info "No install required:" websocat already present
      else
        (exec_sudo curl -o /usr/local/bin/websocat -L https://github.com/vi/websocat/releases/download/v1.13.0/websocat.x86_64-unknown-linux-musl; exec_sudo chmod a+x /usr/local/bin/websocat)
      fi
elif [ "$os" == "macos" ]
  then
    if which brew >/dev/null
      then
        required_packages= 
        for pkg in make pwgen jq yq websocat inkscape imagemagick semgrep comby python fastlane cocoapods expo-orbit watchman zulu@17 android-platform-tools android-commandlinetools bundletool go pnpm watchexec crowdin
          do
            cmd=$pkg
            check_cmd=which
            [ "$pkg" == "imagemagick" ] && cmd=magick
            [ "$pkg" == "python" ] && cmd=python3
            [ "$pkg" == "cocoapods" ] && cmd=pod
            [ "$pkg" == "expo-orbit" ] && check_cmd="brew list"
            [ "${pkg/android/}" != "$pkg" ] && check_cmd="brew list"
            [ "${pkg/zulu/}" != "$pkg" ] && check_cmd="brew list"
            $check_cmd $cmd > /dev/null || required_packages="$required_packages $pkg"
          done
        if [ "$required_packages" == "" ]
          then
            show_info "All requirements met" so not installing brew packages
          else
            show_heading "Setting up brew packages" that are requirements for building ios app on macos: $required_packages
            brew install $required_packages
          fi
      else
        show_error "Brew not found but is required:" please install homebrew before continuing
        exit 1
      fi
  show_info "Checking other build requirements" "for iOS builds"

  # Check required certificates - see https://stackoverflow.com/a/78231028/120398 
  target_keychain=~/Library/Keychains/login.keychain-db
  # to get these sha checks, download the certificate and then openssl x509 -noout -fingerprint -sha1 -inform der -in ~/Downloads/AppleWWDRCAG3.cer | sed 's/://g'
  for cert_sha_pair in AppleWWDRCAG3.cer:06EC06599F4ED0027CC58956B4D3AC1255114F35 AppleWWDRCAG6.cer:0BE38BFE21FD434D8CC51CBE0E2BC7758DDBF97B
    do
      cert_filename="${cert_sha_pair%:*}"
      cert_sha="${cert_sha_pair#*:}"
      if ! security find-certificate -a -c "Apple Worldwide Developer Relations Certification Authority" -Z "${target_keychain}" | grep ${cert_sha} >/dev/null
        then
          show_heading "Installing certificate" $cert_filename
          curl https://www.apple.com/certificateauthority/$cert_filename -o ~/Downloads/$cert_filename
          security add-trusted-cert -d -r unspecified -k "${target_keychain}" ~/Downloads/$cert_filename
        fi
    done

  # Check Xcode location - see https://stackoverflow.com/a/19529693/120398
  # This could be done differently e.g. checking that the right executables are available at this location
  expected_xcode=/Applications/Xcode.app/Contents/Developer
  if [ "$(xcode-select -p)" != "$expected_xcode" ]
    then
      show_heading "Correcting xcode location" "which will require password for sudo rights"
      exec_sudo xcode-select -s "$expected_xcode"
    fi
fi

show_heading "Setting up nvm" and node
export NVM_DIR="$HOME/.nvm"
export NVM_VER=0.40.1
export NODE_VER=20
if [ ! -d "$NVM_DIR/.git" ]
  then
    show_info "Installing nvm" version $NVM_VER
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VER/install.sh | bash
  fi
# this is manually sourcing nvm so we can use its functions
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
show_info "Checking node" version $NODE_VER
nvm ls $NODE_VER || {
  show_info "Installing node" version $NODE_VER
  nvm install $NODE_VER
}

show_info "Checking yarn" in node $NODE_VER
(
  nvm use $NODE_VER
  which yarn > /dev/null || npm install -g yarn
)

if [ "$do_android" == 1 ]; then
  show_heading "Installing Android tools" "and checking that licenses have been accepted (on $os)"

  new_android_home=$(check_android_home) || exit 1
  if [ "$new_android_home" != "" ]
    then
      export ANDROID_HOME="$new_android_home"
      show_info "Default Android SDK" "found at $ANDROID_HOME"
    fi

  if [ "${os/linux/}" != "$os" ]
    then
      # we have to install cmdline-tools manually on Linux
      [ -d $ANDROID_HOME/cmdline-tools ] || {
        show_info "Installing Android SDK Manager" "into $ANDROID_HOME"
        downloads_dir="$script_dir/downloads"
        mkdir -p "$downloads_dir"
        commandlinetools_url="$(curl -s 'https://developer.android.com/studio#command-line-tools-only' | grep 'href="[^"]*commandlinetools-linux.*latest[.]zip"' | sed 's/^.*href="\([^"]*\)".*/\1/g')"
        commandlinetools_zip="$downloads_dir/$(basename "$commandlinetools_url")"
        [ -f "$commandlinetools_zip" ] || {
          show_info --oneline "Downloading latest commandlinetools" "from $commandlinetools_url into $commandlinetools_zip"
          curl -o "$commandlinetools_zip" "$commandlinetools_url" || { show_error "Could not download" "$commandlinetools_url" ; exit 1 ; }
        }
        show_info --oneline "Unpacking latest commandlinetools" "from $commandlinetools_zip into $ANDROID_HOME"
        unzip -d "$ANDROID_HOME" "$commandlinetools_zip"
      }
      sdkmanager_params="--sdk_root=$ANDROID_HOME"
    fi

  which sdkmanager >/dev/null 2>&1 || export PATH="$PATH:$ANDROID_HOME/cmdline-tools/bin"

  which sdkmanager >/dev/null 2>&1 || {
    show_error "Android SDK Manager not found;" "check that you have the commandlinetools installed"
    exit 1
  }

  show_info "Checking License Acceptance" "for Android SDK packages; accept as required"
  sdkmanager $sdkmanager_params --licenses

  show_info --oneline "Checking Android Versions" "configured in social-app"
  android_versions="$($script_dir/selfhost_scripts/get-social-app-android-build-properties.js)"
  android_platform="$(echo "$android_versions" | jq -r .compileSdkVersion)"
  android_build_tools="$(echo "$android_versions" | jq -r .buildToolsVersion)"
  # - In "SDK Platforms": "Android x" (where x is Android's current version).
  # - In "SDK Tools": "Android SDK Build-Tools" and "Android Emulator" are required.
  android_reqs="platform-tools platforms;android-$android_platform build-tools;$android_build_tools emulator ndk"
  android_installed="$(sdkmanager $sdkmanager_params --list_installed)"
  needed_android_reqs=""
  for android_req in $android_reqs
    do
      echo "$android_req" | grep "$android_req" >/dev/null || needed_android_reqs="$needed_android_reqs $android_req"
    done
  if [ "$needed_android_reqs" != "" ]
    then
      for android_req in $android_reqs
        do
          show_info "Installing Android SDK" "$android_req"
          sdkmanager $sdkmanager_params --install $android_req
        done
    else
      show_info "Android SDK requirements already installed:" "no install required"
    fi
fi

show_heading "Building internal tool" "selfhost_scripts/apiImpl" 
(
  cd selfhost_scripts/apiImpl
  nvm use 20
  npm install
)

show_heading "Setting up environment" "for selfhost_scripts"
(
  cd selfhost_scripts
  setup_python_venv_with_requirements
)

show_heading "Setting up environment" "for selfhost_scripts/compose2envtable"
(
  cd selfhost_scripts/compose2envtable
  setup_python_venv_with_requirements
)

show_heading "Setting up environment" "for selfhost_scripts/utils"
(
  cd selfhost_scripts/utils
  setup_python_venv_with_requirements
)

show_heading "Setting up environment" "for rebranding"
(
  cd rebranding
  setup_python_venv_with_requirements
  venv/bin/pip show -q selfhost_scripts || venv/bin/pip install -e ../selfhost_scripts
)

