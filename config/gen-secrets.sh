#!/usr/bin/env bash

# Delegate secret generation to Python program
# This maintains backwards compatibility while using the new Python-based system

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Use Python program to generate secrets
exec "${WORK_DIR}/selfhost_scripts/gen_secrets.py" \
    --template-file "${WORK_DIR}/config/secrets-passwords.env.example" \
    "${WORK_DIR}/config/secrets-passwords.env" \
    "$@"
