#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OVMF="$(brew --prefix)/share/qemu/edk2-x86_64-code.fd"
VARS=build/ovmf-vars.fd
[ -f "$VARS" ] || cp "$(brew --prefix)/share/qemu/edk2-i386-vars.fd" "$VARS"
MODE=uefi; ACCEL=hvf; CPU=host; EXTRA=(); DISPLAY_ARG=(-display cocoa,show-cursor=on)
while [ $# -gt 0 ]; do
  case "$1" in
    --bios)  MODE=bios ;;
    --tcg)   ACCEL=tcg; CPU=qemu64 ;;
    --debug) ACCEL=tcg; CPU=qemu64; EXTRA+=(-d int,cpu_reset -D build/qemu.log) ;;
    --headless) DISPLAY_ARG=(-display none) ;;
    --vnc)   DISPLAY_ARG=(-vnc :1) ;;
    *) echo "unknown flag $1"; exit 1 ;;
  esac; shift
done
ARGS=(-M q35 -accel "$ACCEL" -cpu "$CPU" -m 512M -smp 1
      -cdrom build/gzowo.iso -boot d
      -serial stdio -no-reboot -no-shutdown
      -device isa-debug-exit,iobase=0xf4,iosize=0x04)
[ "$MODE" = uefi ] && ARGS+=(-drive if=pflash,unit=0,format=raw,readonly=on,file="$OVMF"
                            -drive if=pflash,unit=1,format=raw,file="$VARS")
exec qemu-system-x86_64 "${ARGS[@]}" "${DISPLAY_ARG[@]}" "${EXTRA[@]}"
