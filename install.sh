#!/usr/bin/env bash

# kstorage-cli installation script
# https://github.com/koompi/kstorage-cli

set -e

# Configuration
REPO_URL="https://raw.githubusercontent.com/koompi/kstorage-cli/master"
SCRIPT_NAME="kstorage"
INSTALL_DIR="/usr/local/bin"

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*|Darwin*)
        ;;
    *)
        echo "Unsupported OS: ${OS}"
        exit 1
        ;;
esac

echo "Installing kstorage CLI..."

# Check for dependencies
check_dep() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: $1 is not installed. Please install it first."
        exit 1
    fi
}

check_dep curl
check_dep jq

# Download the script
echo "Downloading kstorage script..."
curl -fsSL "${REPO_URL}/${SCRIPT_NAME}" -o "${SCRIPT_NAME}"

# Move to install directory
echo "Moving to ${INSTALL_DIR}/${SCRIPT_NAME}..."
if [ -w "${INSTALL_DIR}" ]; then
    mv "${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
else
    echo "Requires sudo to move to ${INSTALL_DIR}"
    sudo mv "${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
fi

# Make it executable
echo "Making it executable..."
if [ -w "${INSTALL_DIR}/${SCRIPT_NAME}" ]; then
    chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
else
    sudo chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
fi

echo "Successfully installed kstorage to ${INSTALL_DIR}/${SCRIPT_NAME}"
echo "You can now run it using: kstorage"
