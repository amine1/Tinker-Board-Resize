#!/bin/bash
# Script to resize a Tinker Board 2 Android image
# Author: Amine Ouhamou

# ************** Configuration **************
DISK_IMAGE="in_tinker_board.img"
TARGET_PARTITION=16  # User data partition
SECTOR_SIZE=512      # Standard sector size (512 bytes)
BLOCK_SIZE=4096      # ext4 block size (4 KiB)
MIN_FREE_SPACE_MB=512  # Minimum free space in MB after resizing
# *******************************************

# Enable error handling
set -e

echo "========== Phase 1: Preparation =========="
# Mount the image as a loop device
LOOP_DEVICE=$(sudo losetup -f --show -P "$DISK_IMAGE")
PARTITION="${LOOP_DEVICE}p${TARGET_PARTITION}"
echo "Used loop device: $LOOP_DEVICE"
echo "Target partition: $PARTITION"

# Determine the start sector of the partition
echo "Determine the start sector of the partition..."
START_SECTOR=$(sudo parted "$LOOP_DEVICE" -ms unit s print | grep "^${TARGET_PARTITION}" | cut -d: -f2 | sed 's/s//')
if ! [[ "$START_SECTOR" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not determine the start sector of the partition."
    echo "Please check the partition table with 'fdisk -l' or 'parted'."
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi
echo "Start sector of the partition: $START_SECTOR"

# Check the file system type
FS_TYPE=$(sudo blkid -o value -s TYPE "$PARTITION")
if [ "$FS_TYPE" != "ext4" ]; then
    echo "Unsupported file system: $FS_TYPE"
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi
echo "File system type: $FS_TYPE"

# Ensure the partition is not mounted
if mount | grep -q "$PARTITION"; then
    echo "Error: Partition is still mounted. Please unmount first!"
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi

echo "========== Phase 2: File system check =========="
# Check and repair the file system with automatic quota update confirmation
sudo e2fsck -fy "$PARTITION"

echo "========== Phase 3: Determine minimum size =========="
# Determine the minimum size of the file system (in blocks)
MIN_BLOCKS=$(sudo resize2fs -P "$PARTITION" | awk -F': ' '{print $2}')
if ! [[ "$MIN_BLOCKS" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid block count ($MIN_BLOCKS) from resize2fs."
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi

# Consider additional free space
FREE_SPACE_BLOCKS=$((MIN_FREE_SPACE_MB * 1024 * 1024 / BLOCK_SIZE))
TARGET_BLOCKS=$((MIN_BLOCKS + FREE_SPACE_BLOCKS))
echo "Minimum size of the file system: $MIN_BLOCKS blocks"
echo "Target size of the file system with free space: $TARGET_BLOCKS blocks"

echo "========== Phase 4: Resize file system =========="
# Resize the file system to the target size
sudo resize2fs "$PARTITION" "$TARGET_BLOCKS"

echo "========== Phase 5: Adjust partition =========="
# Calculate the new partition size in sectors
NEW_SIZE_SECTORS=$((TARGET_BLOCKS * BLOCK_SIZE / SECTOR_SIZE))
END_SECTOR=$((START_SECTOR + NEW_SIZE_SECTORS - 1))
if [ "$END_SECTOR" -le "$START_SECTOR" ]; then
    echo "Error: End sector is before the start sector."
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi
echo "New partition size in sectors: $NEW_SIZE_SECTORS"
echo "New end sector of the partition: $END_SECTOR"

# Adjust the partition (manually confirm warning)
sudo parted --script "$LOOP_DEVICE" resizepart "$TARGET_PARTITION" "${END_SECTOR}s"

# Wait for user input (y or n)
read -p "Are you sure you want to continue (y/n)? " choice
if [[ "$choice" != "y" ]]; then
  echo "Operation cancelled by user."
  sudo losetup -d "$LOOP_DEVICE"
  exit 1
fi

echo "========== Phase 6: Trim image =========="
# Calculate the new image size based on the last sector of the last partition
LAST_SECTOR=$(sudo fdisk -l "$LOOP_DEVICE" | grep "^$LOOP_DEVICE" | tail -n1 | awk '{print $3}')
if ! [[ "$LAST_SECTOR" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid last sector ($LAST_SECTOR)."
    sudo losetup -d "$LOOP_DEVICE"
    exit 1
fi

NEW_IMG_SIZE=$(( (LAST_SECTOR + 1) * SECTOR_SIZE ))
sudo truncate --size="$NEW_IMG_SIZE" "$DISK_IMAGE"
echo "New image trimmed to ${NEW_IMG_SIZE} bytes."

echo "========== Phase 7: Remove loop device =========="
# Remove the loop device
sudo losetup -d "$LOOP_DEVICE"

echo "========== Successfully completed! =========="
