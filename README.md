# Gzowo OS

A from-scratch x86_64 operating system. No Linux underneath, no borrowed desktop —
the bootloader hands over a framebuffer and everything after that is ours: memory
management, interrupts, timers, drivers, an anti-aliased software renderer, an
animation system, and a macOS-flavoured desktop shell.

Target hardware: an HP Pavilion Gaming laptop, booted from a USB stick over UEFI.
Daily development happens in QEMU on a Mac.

## Status

| Milestone | What | State |
|---|---|---|
| M0 | Toolchain, Limine boot, framebuffer | done |
| M1 | GDT/IDT, PMM/VMM, heap, LAPIC timer, RTC | in progress |
| M2 | PS/2 keyboard and mouse | planned |
| M3 | Graphics library, anti-aliased text | planned |
| M4 | Animation, boot splash, lock screen | planned |
| M5 | Desktop, windows, dock, menu bar | planned |
| M6 | ACPI via LAI, real battery readout | planned |
| M7 | Real-hardware polish | planned |

## Build

Requires macOS with Homebrew: `brew install llvm lld nasm xorriso qemu`.

```
cd v1
make        # kernel.elf
make iso    # hybrid BIOS+UEFI bootable ISO
make run    # boot it in QEMU
```

`tools/smoke.sh 10` boots headless, captures the serial log and a screenshot.
`tools/write-usb.sh /dev/diskN` writes the ISO to a USB stick after an explicit
confirmation; it refuses anything that is not an external removable disk.

## Design

Everything is drawn by hand into a software framebuffer: rounded rectangles with
anti-aliased coverage, alpha blending, cached blurs for translucency, drop shadows,
and glyphs rasterised from Inter through stb_truetype. There is no GPU driver and
no graphics library — the whole frame has to fit in a few milliseconds of CPU time.

Internal documents live in `Niepotrzebne/`: `PLAN.md` is the implementation plan,
`UIBRIEF.md` the visual specification.

## Third-party

| Component | License |
|---|---|
| [Limine](https://github.com/limine-bootloader/limine) bootloader | BSD-2-Clause |
| [LAI](https://github.com/managarm/lai) ACPI interpreter | MIT |
| [stb_truetype](https://github.com/nothings/stb) | public domain / MIT |
| [Inter](https://rsms.me/inter/) typeface | SIL OFL 1.1 |
