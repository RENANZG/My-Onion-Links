#!/usr/bin/env bash

#######################################################################
# File Name    : tails_install_v2.sh
# Description  : Download, verify and write Tails from Debian.
# Dependencies : curl gpg grep find dosfstools coreutils bash-builtins
# Usage        : • Make the script executable with
#                sudo chmod +x ~/Downloads/tails_install_v2.sh
#                • Run the script with:
#                sudo bash ~/Downloads/tails_install_v2.sh
# Author       : Me and the bois
# License      : Free of charge, no warranty
# Last edited  : 2024-10-01
# Based on     : https://tails.net/install/expert/index.en.html
#                https://github.com/hellais/TAILS-OSX
#######################################################################

# Variables
TAILS_DATA_DIR="tails_data"
USB_PART_NAME="TAILSLIVE"
TAILS_BASE_URL="http://dl.amnesia.boum.org/tails/stable/"
TAILS_SIG_URL="https://tails.net/torrents/files/"
TAILS_KEY_URL="https://tails.net/tails-signing.key"

# Function to clean up the old tails_data directory if it exists
clean_up() {
  if [ -d "$TAILS_DATA_DIR" ]; then
    find "$TAILS_DATA_DIR" -mindepth 1 -delete
    echo -e "\nCleaned up the old $TAILS_DATA_DIR/ directory!\n"
  else
    echo -e "\n$TAILS_DATA_DIR/ directory does not exist.\n"
  fi
}

# Function to download the latest Tails version
download_tails_version() {
  echo -e "\n[+] Detecting the latest Tails version..."
  local version_page=$(curl -s -L $TAILS_BASE_URL)

  TAILS_VERSION=$(echo "$version_page" | grep -oP '(?<=href=")[^"]*(tails-amd64-)[0-9]+\.[0-9]+' | head -1 | grep -oP '[0-9]+\.[0-9]+')

  if [ -z "$TAILS_VERSION" ]; then
    echo -e "\nERROR! Could not detect the latest version of TAILS."
    exit 1
  fi
  echo -e "\n[+] Latest Tails version detected: $TAILS_VERSION"

  TAILS_ISO_URL="${TAILS_BASE_URL}tails-amd64-${TAILS_VERSION}/tails-amd64-${TAILS_VERSION}.img"
  TAILS_SIG_URL="${TAILS_SIG_URL}tails-amd64-${TAILS_VERSION}.img.sig"
}

# Function to choose a target disk for the Tails image
choose_target_disk() {
  echo -e "\nWhat disk would you like to use for the Tails image?"
  lsblk
  echo -e "\nFor example: /dev/sdc"
  read -r TARGET_DISK
}

# Function to create a FAT32 partition on the target disk
create_fat32_partition() {
  local TARGET_DISK=$1

  # Unmount any existing partitions on the target disk
  echo -e "\nUnmounting any existing partitions on $TARGET_DISK..."
  umount "${TARGET_DISK}"* || echo "No partitions to unmount on $TARGET_DISK"

  if [ "$(uname -s)" == "Linux" ]; then
    echo -e "\nErasing $TARGET_DISK and creating a FAT32 partition..."
    mkfs.vfat -I -F 32 -n "$USB_PART_NAME" "$TARGET_DISK"
    if [ $? -ne 0 ]; then
      echo -e "\nERROR! Failed to create FAT32 partition on $TARGET_DISK."
      exit 1
    fi
  else
    echo -e "\nCurrently don't support building image on this platform."
    exit 1
  fi
}

# Function to download the Tails image
download_tails_image() {
  echo -e "\n[+] Downloading Tails image..."

  # Download the Tails image using curl with resume capability
  curl --retry 5 --retry-delay 10 --max-time 3600 -L -C - -o "$TAILS_DATA_DIR/tails.img" "$TAILS_ISO_URL"

  # Check if the download was successful by comparing the size of the downloaded file with the expected size
  local expected_size=$(curl -sI "$TAILS_ISO_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
  local actual_size=$(stat -c%s "$TAILS_DATA_DIR/tails.img")

  if [ "$actual_size" != "$expected_size" ]; then
    echo -e "\nERROR! Downloaded file size does not match the expected size. The file may be incomplete."
    exit 1
  fi

  echo -e "\n[+] Download of Tails image completed."
}

# Function to verify Tails IMG
verify_tails_image() {
  # Download the signing key and signature file
  curl -o "$TAILS_DATA_DIR/tails-signing.key" -L "$TAILS_KEY_URL"
  curl -o "$TAILS_DATA_DIR/tails.img.sig" -L "$TAILS_SIG_URL"

  # Import the signing key into a temporary keyring
  gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --import "$TAILS_DATA_DIR/tails-signing.key"

  # Verify the key fingerprint
  if gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --fingerprint 58ACD84F | grep -q "A490 D0F4 D311 A415 3E2B  B7CA DBB8 02B2 58AC D84F"; then
    echo -e "\nThe imported Tails developer key is valid."
  else
    echo -e "\nERROR! The imported key does not seem to be the right one. Something is fishy!"
    exit 1
  fi

  # Set the key as ultimately trusted without interactive prompts
  gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --batch --command-fd 0 <<EOF
trust
5
save
EOF

  echo -e "\nThe key is now set to ultimate trust."

  # Verify the Tails image signature
  if gpg --no-default-keyring --keyring "$TAILS_DATA_DIR/tmp_keyring.pgp" --verify "$TAILS_DATA_DIR/tails.img.sig" "$TAILS_DATA_DIR/tails.img" > /dev/null 2>&1; then
    echo -e "\nThe .img seems legit."
  else
    echo -e "\nERROR! The image does not seem to be signed by the Tails key. Something is fishy!"
    exit 1
  fi
}


# Function to write the Tails image to the target disk
write_tails_image() {
  choose_target_disk

  echo -e "\nWarning: $TARGET_DISK will be erased. Do you wish to continue [y|n]? "
  read -r ans

  if [[ $ans =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "\nOk, you wanted it!"
  else
    echo -e "\nBye!"
    exit 1
  fi

  if [ -f "$TAILS_DATA_DIR/tails.img" ]; then
    echo -e "\n[+] Found Tails image in $TAILS_DATA_DIR/tails.img. Using it!"
  else
    download_tails_image
  fi

  create_fat32_partition "$TARGET_DISK"

  echo -e "\n[+] Copying live directory, please wait..."
  dd if="$TAILS_DATA_DIR/tails.img" of="$TARGET_DISK" bs=16M oflag=direct status=progress

  echo -e "\nAll done!"
}

# Main script execution
main() {
  mkdir -p "$TAILS_DATA_DIR"
  clean_up
  download_tails_version
  download_tails_image
  verify_tails_image
  write_tails_image
}

# Invoke the main function
main
