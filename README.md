# README: Resizing a Tinker Board 2 Android Image

This script is designed to shrink the user partition of an Android image for the Tinker Board 2 and remove unused space.

## Prerequisites

### Required Tools
Ensure the following tools are installed on your system:
- `losetup` (part of `util-linux`)
- `parted`
- `fdisk`
- `resize2fs`
- `e2fsck`
- `truncate`
- `blkid`

### Permissions
The script requires root privileges since it interacts with block devices. Run it using `sudo`.

## Usage

### 1. Prepare the Script
Save the script in a file, e.g., `resize_tinker_board.sh`, and make it executable:
```bash
chmod +x resize_tinker_board.sh
```

### 2. Prepare the Input File
Place the Android image you want to resize in the same directory as the script and name it according to the script configuration (`in_tinker_board.img`).
If the filename is different, update the `DISK_IMAGE` variable in the script.

### 3. Run the Script
Execute the script with root privileges:
```bash
sudo ./resize_tinker_board.sh
```

### Script Code
```bash
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

...

# Remove the loop device
sudo losetup -d "$LOOP_DEVICE"

echo "========== Successfully completed! =========="
```

### 4. Verify After Execution
After successful execution, check the resized image using:
```bash
fdisk -l in_tinker_board.img
```
This ensures that the new size is correct.

### 5. Use the Resized Image
The resized image is now ready to be flashed onto an SD card or eMMC storage, saving space.

#### Important: First Boot After Resizing
After flashing the resized image onto the Tinker Board 2, you must boot the device **twice**. On the first boot, Android will automatically adjust the user partition to match the new configuration. The second boot ensures all changes take effect properly.

## Troubleshooting
If errors occur:
- Use `fdisk -l` or `parted` to verify that the image is recognized correctly.
- Ensure the partition is not mounted.
- If `resize2fs` fails, try running a manual filesystem check:
  ```bash
  sudo e2fsck -f in_tinker_board.img
  ```

If further issues arise, review the console output for clues or enable debugging by adding `set -x` to the script.

