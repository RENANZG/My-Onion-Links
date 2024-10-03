#!/usr/bin/env bash

########################################################################
# File Name    : tails_install_v1.sh
# Description  : Install Tails from Debian or Ubuntu.
# Dependencies : curl, gpg, grep, find, coreutils, bash-builtins
# Based on     : https://tails.net/install/expert/index.en.html
#                https://github.com/hellais/TAILS-OSX 
# Usage        : • Make the script executable with 
#                sudo chmod +x ~/Downloads/tails_install_v1.sh
#                • Run the script with:   
#                sudo bash ~/Downloads/tails_install_v1.sh
# Author       : Me and the bois
# License      : Free of charge, no warranty
# Last edited  : 2024-06-01
########################################################################

# Function to clean up the tails_data directory
clean_up() {
  find tails_data -not -path tails_data -delete 
  echo "Cleaned up the tails_data/ directory!"
  echo "You can now re-run the script with:"
  echo "$0"

  exit 0
}

# Check if the script is invoked with "clean" argument and perform cleanup
if [ "$1" == "clean" ]; then
  clean_up
fi

# Function to download the latest Tails version
download_tails_version() {
  echo "[+] Detecting the latest Tails version..."
  TAILS_VERSION=$(curl -s -L http://dl.amnesia.boum.org/tails/stable/ | sed -n "s/^.*\(tails-amd64-[0-9.]*\).*$/\1/p")
  if [ -z "$TAILS_VERSION" ]; then
    echo "Could not detect the latest version of TAILS."
    exit 1
  fi
  echo "[+] Latest Tails version detected: $TAILS_VERSION"

  TAILS_ISO_URL="http://dl.amnesia.boum.org/tails/stable/$TAILS_VERSION/$TAILS_VERSION.img"
  TAILS_SIG_URL="https://tails.net/torrents/files/$TAILS_VERSION.img.sig"
  TAILS_KEY_URL="https://tails.net/tails-signing.key"
  USB_PART_NAME="TAILSLIVE"
}

# Function to create a FAT32 partition on the target disk
create_fat32_partition() {
  local TARGET_DISK=$1

  if [ "$(uname -s)" == "Linux" ]; then
    echo "Erasing $TARGET_DISK and creating a FAT32 partition..."
    mkfs.vfat -F 32 -n $USB_PART_NAME $TARGET_DISK
  else
    echo "Currently don't support building image on this platform"
  fi
}

# Function to mount the USB disk and return the mount point
mount_usb_disk() {
  local TARGET_DISK=$1
  local mount_point="/media/$USB_PART_NAME"

  if [ "$(uname -s)" == "Linux" ]; then
    mkdir -p "$mount_point"
    mount $TARGET_DISK "$mount_point"
  else
    echo "Currently don't support building image on this platform"
    exit 1
  fi

  echo "$mount_point"
}

# Function to verify Tails IMG
verify_tails_image() {
  curl -o tails_data/tails-signing.key -L $TAILS_KEY_URL
  curl -o tails_data/tails.img.sig -L $TAILS_SIG_URL
 
  rm -f tails_data/tmp_keyring.pgp
  gpg --no-default-keyring --keyring tails_data/tmp_keyring.pgp --import tails_data/tails-signing.key

  if gpg --no-default-keyring --keyring tails_data/tmp_keyring.pgp --fingerprint 58ACD84F | grep "A490 D0F4 D311 A415 3E2B  B7CA DBB8 02B2 58AC D84F"; then
    echo "The imported Tails developer key is valid."
  else
    echo "ERROR! The imported key does not seem to be the right one. Something is fishy!"
    exit 1
  fi
  
  if gpg --no-default-keyring --keyring tails_data/tmp_keyring.pgp --verify tails_data/tails.img.sig; then
    echo "The .img seems legit."
  else
    echo "ERROR! The ISO does not seem to be signed by the Tails key. Something is fishy!"
    exit 1
  fi
}

# Function to download the Tails image
download_tails_image() {
  echo "[+] Downloading $TAILS_VERSION image."
  curl -o tails_data/tails-tmp.img -L $TAILS_ISO_URL
  if [ $? -ne 0 ]; then
    echo "ERROR! Failed to download the Tails image."
    exit 1
  fi
  mv tails_data/tails-tmp.img tails_data/tails.img
}

# Function to choose a target disk for the Tails image
choose_target_disk() {
  echo "What disk would you like to use for the Tails image?"
  lsblk
  echo "For example: /dev/sdc"
  read TARGET_DISK
}

# Function to write the Tails image to the target disk
write_tails_image() {
  choose_target_disk

  echo "Warning: $TARGET_DISK will be erased. Do you wish to continue [y|n]? "
  read ans 
  
  if [[ $ans =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Ok, you wanted it!"
  else
    echo "Bye!"
    exit 1
  fi

  if [ -f "tails_data/tails.img" ]; then
    echo "[+] Found Tails image in tails_data/tails.img. Using it!"
  else
    download_tails_image
  fi

  create_fat32_partition "$TARGET_DISK"
  
  echo "[+] Copying live directory, please wait..."
  dd if="tails_data/tails.img" of="$TARGET_DISK" bs=16M oflag=direct status=progress
  
  echo "All done"
}

# Main script execution
main() {
  mkdir -p tails_data
  download_tails_version
  write_tails_image
}

# Invoke the main function
main
