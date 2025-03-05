#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

if [ "$os" == "linux-ubuntu" ]
  then
    show_heading "Setting up apt packages" that are requirements for building running and testing these docker images
    if dpkg-query -l make pwgen jq yq
      then
        show_info "No install required:" all packages already installed
      else
        sudo apt update
        # make is used to run setup scripts etc
        # pwgen is used to generate new securish passwords
        # jq and yq are used in extracted json and yaml data for config and tests
        sudo apt install -y make pwgen jq yq
      fi
    
    show_heading "Setting up websocat" directly from executable download, in /usr/local/bin
    if [ -x /usr/local/bin/websocat ] && websocat --version
      then
        show_info "No install required:" websocat already present
      else
        (sudo curl -o /usr/local/bin/websocat -L https://github.com/vi/websocat/releases/download/v1.13.0/websocat.x86_64-unknown-linux-musl; sudo chmod a+x /usr/local/bin/websocat)
      fi
elif [ "$os" == "macos" ]
  then
    if which brew >/dev/null
      then
        required_packages= 
        for pkg in make pwgen jq yq websocat inkscape imagemagick semgrep comby python fastlane
          do
            cmd=$pkg
            [ "$pkg" == "imagemagick" ] && cmd=magick
            [ "$pkg" == "python" ] && cmd=python3
            which $cmd > /dev/null || required_packages="$required_packages $pkg"
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

show_heading "Building internal tool" "ops-helper/apiImpl" 
(
  cd ops-helper/apiImpl
  nvm use 20
  npm install
)

show_heading "Setting up environment" "for ops-helper/compose2envtable"
(
  cd ops-helper/compose2envtable
  [ -d venv ] || python3 -m venv venv
  . venv/bin/activate
  python -m pip install -U pip
  python -m pip install -r requirements.txt
)

show_heading "Setting up environment" "for ops-helper/utils"
(
  cd ops-helper/utils
  [ -d venv ] || python3 -m venv venv
  . venv/bin/activate
  python -m pip install -U pip
  python -m pip install -r requirements.txt
)

show_heading "Setting up environment" "for rebranding"
(
  cd rebranding
  [ -d venv ] || python3 -m venv venv
  . venv/bin/activate
  python -m pip install -U pip
  python -m pip install -r requirements.txt
)

