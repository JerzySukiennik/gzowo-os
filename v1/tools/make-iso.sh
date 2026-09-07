#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
R=build/iso_root
rm -rf "$R"
mkdir -p "$R/boot/limine" "$R/EFI/BOOT"
cp build/kernel.elf "$R/boot/"
cp "${LIMINE_CONF:-limine.conf}" "$R/boot/limine/limine.conf"
cp third_party/limine/limine-bios.sys third_party/limine/limine-bios-cd.bin third_party/limine/limine-uefi-cd.bin "$R/boot/limine/"
cp third_party/limine/BOOTX64.EFI "$R/EFI/BOOT/"
xorriso -as mkisofs -quiet -R -r -J \
  -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
  -hfsplus -apm-block-size 2048 \
  --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
  --protective-msdos-label "$R" -o build/gzowo.iso
./third_party/limine/limine bios-install build/gzowo.iso >/dev/null
echo "  built build/gzowo.iso"
