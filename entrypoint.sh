#!/bin/bash

set -e

BASHRC_FILE="${HOME}/.bashrc"
VENV_DIR="${HOME}/.venv"
VENV_ACTIVATE_SCRIPT="${VENV_DIR}/bin/activate"

# Set up Python virtual environment
echo "Creating Python virtual environment in ${VENV_DIR}"
python3 -m venv --prompt dev "${VENV_DIR}"
source "${VENV_ACTIVATE_SCRIPT}"

# Install pip dependencies
python -m pip install --upgrade pip
pip install \
lit

# Add venv activation to .bashrc if not already present for interactive shells
if ! grep -qF -- "source ${VENV_ACTIVATE_SCRIPT}" "${BASHRC_FILE}" 2>/dev/null; then
    echo "Adding Python virtual environment activation to ${BASHRC_FILE}"
    echo -e "\n# Activate Python virtual environment" >> "${BASHRC_FILE}"
    echo "source ${VENV_ACTIVATE_SCRIPT}" >> "${BASHRC_FILE}"
fi

# Execute the command passed to the container
exec "$@"
