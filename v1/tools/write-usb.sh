#!/bin/bash
# Write build/gzowo.iso to a USB stick. Refuses internal disks. Never runs without an argument.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
  echo "usage: tools/write-usb.sh /dev/diskN"
  echo
  diskutil list
  exit 1
fi
DISK="$1"
[ -f build/gzowo.iso ] || { echo "build/gzowo.iso missing — run 'make iso' first"; exit 1; }
case "$DISK" in /dev/disk[0-9]*) ;; *) echo "refusing: '$DISK' is not a /dev/diskN path"; exit 1 ;; esac

INFO=$(diskutil info "$DISK")
echo "$INFO" | grep -E "Device / Media Name|Disk Size|Removable Media|Device Location|Virtual|Whole" || true
echo

echo "$INFO" | grep -q "Device Location: *External" || { echo "refusing: $DISK is not an external disk"; exit 1; }
echo "$INFO" | grep -qE "Removable Media: *(Removable|Fixed)" || { echo "refusing: cannot confirm removable media"; exit 1; }
if diskutil info / 2>/dev/null | grep -q "Part of Whole: *${DISK#/dev/}$"; then
  echo "refusing: $DISK holds the boot volume"; exit 1
fi

SIZE=$(ls -lh build/gzowo.iso | awk '{print $5}')
echo "About to ERASE $DISK and write build/gzowo.iso ($SIZE)."
printf "Type YES to continue: "
read -r ANSWER
[ "$ANSWER" = "YES" ] || { echo "aborted"; exit 1; }

diskutil unmountDisk "$DISK"
sudo dd if=build/gzowo.iso of="/dev/r${DISK#/dev/}" bs=4m status=progress
sync
diskutil eject "$DISK"
echo "done — $DISK is now a Gzowo OS boot stick"
