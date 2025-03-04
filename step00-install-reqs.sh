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
        for cmd in make pwgen jq yq websocat inkscape imagemagick semgrep comby python
          do
            which $cmd > /dev/null || required_packages="$required_packages $cmd"
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
# installing nvm and node
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# this is manually sourcing nvm so we can use its functions
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 20

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

