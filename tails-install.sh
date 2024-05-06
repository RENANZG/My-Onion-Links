#!/bin/bash

#######################################################
##  Install Tails from Debian or Ubuntu, based on:   ##
##                                                   ##
##  https://tails.net/install/expert/index.en.html   ##
##  https://github.com/hellais/TAILS-OSX             ##
##                                                   ##
##  Make it executable:                              ##
##  $ sudo chmod +x ~/Downloads/tails-install.sh     ##
##                                                   ##
##  Then run                                         ##
##  $ sudo bash ~/Downloads/tails-install.sh         ##
##                                                   ##
##  Last edited: 2024-05-01                          ##
#######################################################


if [ "$1" == "clean" ]; then
  find data -not -path data -delete 
  echo "Cleaned up the data/ directory!"
  echo "You can now re-run the script with:"
  echo "$0"

  exit 0
fi

# set -x
TAILS_VERSION=$(curl -s -L http://dl.amnesia.boum.org/tails/stable/ | sed -n "s/^.*\(tails-amd64-[0-9.]*\).*$/\1/p")
if [ -z "$TAILS_VERSION" ]; then
  echo "Could not detect the latest version of TAILS."
  exit 1
fi
TAILS_ISO_URL="http://dl.amnesia.boum.org/tails/stable/$TAILS_VERSION/$TAILS_VERSION.img"
TAILS_SIG_URL="https://tails.net/torrents/files/$TAILS_VERSION.img.sig"
TAILS_KEY_URL="https://tails.net/tails-signing.key"
USB_PART_NAME="TAILSLIVE"

if [ ! -d "data" ]; then
  echo "[+] Creating data/ directory..."
  mkdir data/
fi

create_disk () {
  TARGET_DISK=$1

  # This erases the TARGET disk and creates 1 FAT32 partition that is of the size of the drive.
  if [ "$(uname -s)" == "Linux" ]; then
    echo "Erasing $TARGET_DISK and creating a FAT32 partition..."
    mkfs.vfat -F 32 -n $USB_PART_NAME $TARGET_DISK
  else
    echo "Currently don't support building image on this platform"
  fi
}

mount_disk () {
  # This mounts the USB disk and returns the mount_point of the USB disk
  local __resultvar=$1
  if [ "$(uname -s)" == "Linux" ]; then
    local mount_point="/media/$USB_PART_NAME"
    mkdir -p "$mount_point"
    mount $TARGET_DISK "$mount_point"
  else
    echo "Currently don't support building image on this platform"
    exit 1
      fi
  eval $__resultvar="'$mount_point'"
}

mount_iso () {
  # This mounts the .img and returns its mount point
  local __resultvar=$1
  if [ "$(uname -s)" == "Linux" ]; then
    local mount_point="/media/TAILS_ISO"
    mkdir -p "$mount_point"
    mount -o data/tails.img "$mount_point"
  else
    echo "Currently don't support building image on this platform."
    exit 1
      fi
  eval $__resultvar="'$mount_point'"
}

verify_tails () {
  curl -o data/tails-signing.key -L $TAILS_KEY_URL
  curl -o data/tails.img.sig -L $TAILS_SIG_URL
 
  rm -f data/tmp_keyring.pgp
  gpg --no-default-keyring --keyring data/tmp_keyring.pgp --import data/tails-signing.key

  if gpg --no-default-keyring --keyring data/tmp_keyring.pgp --fingerprint 58ACD84F | grep "A490 D0F4 D311 A415 3E2B  B7CA DBB8 02B2 58AC D84F";then
    echo "The import TAILS developer key is ok."
  else
    echo "ERROR! The imported key does not seem to be right one. Something is fishy!"
    exit 1
  fi
  
  if gpg --no-default-keyring --keyring data/tmp_keyring.pgp --verify data/tails.img.sig; then
    echo "The .img seems legit."
  else
    echo "ERROR! The iso does not seem to be signed by the TAILS key. Something is fishy!"
    exit 1
  fi
}

download_tails () {
  echo "[+] Downloading $TAILS_VERSION image."
  curl -o data/tails-tmp.img -L $TAILS_ISO_URL
  mv data/tails-tmp.img data/tails.img
}

choose_disk () {
  # This lists all the disks in a way that is readable by the user. The read input will then be passed as argument to the create_disk function.
  echo "What disk would you like to use for the TAILS image?"
  lsblk
  echo "for example: /dev/sdc"
  read TARGET_DISK
}

create_image () {
  choose_disk

  echo "Warning: $TARGET_DISK will be erased. Do you wish to continue [y|n]? "
  read ans 
  
  if [[ $ans =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Ok, you wanted it!"
  else
    echo "Bye!"
    exit 1
  fi

  if [ -f "data/tails.img" ]; then
    echo "[+] Found Tails image in data/tails.img. Using it!"
  else
    download_tails
  fi

  create_disk "$TARGET_DISK"
  
  echo "[+] Copying live directory, wait."
     dd if="data/tails.img" of="$TARGET_DISK" bs=16M oflag=direct status=progress
  
  echo "All done"
}


create_image;
