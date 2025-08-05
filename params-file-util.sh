#!/bin/bash

selfhost_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd $selfhost_dir

if [ "$#" == 0 ]
  then
    if [ -f .env ]
      then
        ls -l .env
      else
        echo "No .env file found. Set by running $0 [new_env_file]. Potential options:" >&2
        ls *.env
      fi
  else
    [[ "$1" == "-h" || "$1" == "--help" ]] && { echo "syntax $0 [-d|--delete|new_params_file]" >&2 ; exit 0 ; }
    [[ "$1" == "-d" || "$1" == "--delete" ]] && {
      [ -h .env ] && { echo .env was previously pointing to "$(readlink .env)" ; rm .env ; echo removed symlink ; exit 0 ; }
      [ -f .env ] && { echo .env is not a symlink: not removing, check and adjust manually; ls -l .env ; exit 1 ; }
      echo no .env found >&2 ; exit 1
    }
    [ -f "$1" ] || { echo can not find $1 to use as new environment file >&2 ; exit 1; }
    [ -h .env ] && { echo .env was previously pointing to "$(readlink .env)" ; rm .env ; }
    [ -f .env ] && { echo .env is not a symlink: not removing, check and adjust manually; ls -l .env ; exit 1 ; }
    ln -s "$1" .env
    ls -l .env
  fi


