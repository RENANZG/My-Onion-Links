#!/usr/bin/env bash

#######################################################################
# File Name    : tails_install.sh
# Description  : This script downloads, checks, and writes Tails from a
#                Debian-based system to a USB device.
# Dependencies : curl gpg grep find coreutils bash-builtins
# Usage        : • Make the script executable with:
#                  sudo chmod +x ~/Downloads/tails_install.sh
#                • Run the script with:
#                  sudo bash ~/Downloads/tails_install.sh
# Author       : Me and the bois
# License      : Free of charge, no warranty
# Last edited  : 2024-11-09
# Reference    : https://tails.net/install/expert/index.en.html
#######################################################################

# Variables
TAILS_DATA_DIR="tails_data"
TAILS_BASE_URL="https://mirrors.edge.kernel.org/tails/stable"
TAILS_SIG_URL="https://mirrors.edge.kernel.org/tails/stable"
TAILS_KEY_URL="https://tails.boum.org/tails-signing.key"

# Ensure the script is run with root only when needed
ensure_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo) for disk writing operations."
    exit 1
  fi
}

# Function to clean up the old tails_data directory if it exists
clean_up() {
  if [ -d "$TAILS_DATA_DIR" ]; then
    find "$TAILS_DATA_DIR" -mindepth 1 -delete
    echo -e "\nCleaned up the old $TAILS_DATA_DIR/ directory!\n"
  else
    echo -e "\n$TAILS_DATA_DIR/ directory does not exist.\n"
  fi
}

# Function to check the latest Tails version
download_tails_version() {
  echo -e "\n[+] Detecting the latest Tails version..."

  mkdir -p "$TAILS_DATA_DIR"
  if [ ! -w "$TAILS_DATA_DIR" ]; then
    echo -e "\nERROR! The directory $TAILS_DATA_DIR is not writable by the current user."
    exit 1
  fi

  # Fetch the page and extract the latest version number using regex
  local version_page=$(curl -s -L "$TAILS_BASE_URL")
  TAILS_VERSION=$(echo "$version_page" | grep -oP '(?<=href="tails-amd64-)[0-9]+\.[0-9]+(?=/")' | head -1)

  if [ -z "$TAILS_VERSION" ]; then
    echo -e "\nERROR! Could not detect the latest version of Tails."
    exit 1
  fi
  echo -e "\n[+] Latest Tails version detected: $TAILS_VERSION"

  # Construct the URLs for the image and the signature file using the detected version
  TAILS_ISO_URL="${TAILS_BASE_URL}/tails-amd64-${TAILS_VERSION}/tails-amd64-${TAILS_VERSION}.img"
  TAILS_SIG_URL="${TAILS_BASE_URL}/tails-amd64-${TAILS_VERSION}/tails-amd64-${TAILS_VERSION}.img.sig"
}

# Function to download the Tails image
download_tails_image() {
  echo -e "\n[+] Downloading Tails image...\n"
  curl --retry 5 --retry-delay 10 --max-time 3600 -L -C - -o "$TAILS_DATA_DIR/tails.img" "$TAILS_ISO_URL"
  echo -e "\n[+] Download of Tails image completed.\n"
}

# Function to trust and verify Tails
verify_tails_image() {

  echo -e "\n[+] Checking the integrity and authenticity of the Tails image..."

  # Download the signing key and signature
  curl --retry 5 --retry-delay 10 --max-time 3600 -L -C - -o "$TAILS_DATA_DIR/tails-signing.key" "$TAILS_KEY_URL"
  curl --retry 5 --retry-delay 10 --max-time 3600 -L -C - -o "$TAILS_DATA_DIR/tails.img.sig" "$TAILS_SIG_URL"

  # Import and verify the Tails developer key
  gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --import "$TAILS_DATA_DIR/tails-signing.key"

  # Verify that the key was imported correctly
  if gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --fingerprint 58ACD84F | grep -q "A490 D0F4 D311 A415 3E2B  B7CA DBB8 02B2 58AC D84F"; then
    echo -e "\n[+] The imported Tails developer key is valid.\n"
  else
    echo -e "\nERROR! The imported key does not seem to be the right one. Something is fishy!"
    exit 1
  fi

  # Set trust for the key manually
  echo -e "5\ny\n" | gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --command-fd 0 --edit-key "58ACD84F" trust

  # Verify the image signature
  if gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --verify "$TAILS_DATA_DIR/tails.img.sig" "$TAILS_DATA_DIR/tails.img" > /dev/null 2>&1; then
    echo -e "\n[+] The .img seems legit."
  else
    echo -e "\nERROR! The image does not seem to be signed by the Tails key. Something is fishy!"
    exit 1
  fi
}

# Function to choose a target disk for the Tails image
choose_target_disk() {
  echo -e "\nWhat disk would you like to use for the Tails image?"
  lsblk
  echo -e "\nFor example: /dev/sdc"
  read -r TARGET_DISK
}

# Function to write the Tails image to the target disk (requires root)
write_tails_image() {
  ensure_root

  echo -e "\n[+] Unmounting any existing partitions on $TARGET_DISK..."
  umount "${TARGET_DISK}"* 2>/dev/null || true

  echo -e "\n[+] Writing Tails image to $TARGET_DISK...\n"
  sudo dd if="$TAILS_DATA_DIR/tails.img" of="$TARGET_DISK" bs=16M oflag=direct status=progress
  echo -e "\nAll done!"
}

# Main script execution
main() {
  clean_up
  download_tails_version
  download_tails_image
  verify_tails_image
  choose_target_disk
  write_tails_image
}

# Invoke the main function
main