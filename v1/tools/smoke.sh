#!/bin/bash
# Boot the ISO headless with a VNC-less display, capture serial for N seconds, screenshot.
set -uo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-8}"
OVMF="$(brew --prefix)/share/qemu/edk2-x86_64-code.fd"
VARS=build/ovmf-vars.fd
[ -f "$VARS" ] || cp "$(brew --prefix)/share/qemu/edk2-i386-vars.fd" "$VARS"
rm -f build/serial.log build/screen.ppm build/screen.png
qemu-system-x86_64 -M q35 -accel hvf -cpu host -m 512M -smp 1 \
  -drive if=pflash,unit=0,format=raw,readonly=on,file="$OVMF" \
  -drive if=pflash,unit=1,format=raw,file="$VARS" \
  -cdrom build/gzowo.iso -boot d \
  -serial file:build/serial.log -no-reboot -no-shutdown \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -display none -monitor unix:build/qmp.sock,server,nowait &
QPID=$!
sleep "$SECS"
printf 'screendump build/screen.ppm\n' | nc -U build/qmp.sock >/dev/null 2>&1
sleep 1
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
[ -f build/screen.ppm ] && sips -s format png build/screen.ppm --out build/screen.png >/dev/null 2>&1
echo "--- serial ---"; cat build/serial.log 2>/dev/null
echo "--- screenshot: $(ls -la build/screen.png 2>/dev/null || echo none) ---"
