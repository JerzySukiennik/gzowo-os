# Gzowo OS — v1 Implementation Plan (PLAN.md)

Brief for the Coder agent(s) and the UI/UX agent. Everything here is decided; implement in milestone order. Every milestone ends with a "Verified when" gate that must pass in QEMU before moving on.

## 0. Ground rules for the Coder

1. Freestanding C11 + NASM. No libc. No GNU binutils, no cross-gcc. Toolchain = Homebrew LLVM clang (fallback Apple clang), `ld.lld`, `nasm`, `xorriso`, `qemu`.
2. Never hang without a timeout in hardware init (i8042, PIT, LAPIC calibration). Every wait loop has an iteration cap and logs on timeout.
3. Every subsystem logs to serial (`klog`) on init: `[ok] pmm: 480 MiB usable` style. Failures panic with a visible panic screen.
4. Only the Coder writes code; the UI/UX agent later edits files under `v1/kernel/ui/theme.h`, `ui/*.c` draw functions, and `gfx/wallpaper.c`. Keep drawing code separated from logic so they can.
5. The project directory contains a space (`Gzowo OS`). All Makefile paths are **relative** (run `make` from `v1/`); all shell scripts quote every path.

## 1. Repository layout

```
Gzowo OS/
├── .gitignore                      # v1/build/, v1/*.iso, v1/iso_root/
├── Niepotrzebne/PLAN.md            # this file (internal docs)
└── v1/
    ├── Makefile                    # relative paths only; targets: all, iso, run, run-bios, run-debug, clean, deps
    ├── limine.conf
    ├── linker.ld
    ├── tools/
    │   ├── fetch-deps.sh           # one-time: downloads/pins third_party (see §2)
    │   ├── make-iso.sh             # builds iso_root and gzowo.iso
    │   ├── run-qemu.sh             # UEFI run (default), flags: --bios, --debug, --tcg, --res WxH
    │   └── write-usb.sh            # lists disks, requires explicit /dev/diskN arg, asks "yes", never auto-dd
    ├── third_party/                # VENDORED (committed) — see §2 for why
    │   ├── limine/                 # limine-binary release: limine (host tool, built), BOOTX64.EFI, limine-bios.sys,
    │   │                           #   limine-bios-cd.bin, limine-uefi-cd.bin, limine.h, LICENSE
    │   ├── lai/                    # managarm/lai at pinned commit: core/ helpers/ drivers/ include/ LICENSE
    │   ├── stb/stb_truetype.h      # + LICENSE note (public domain / MIT dual)
    │   └── fonts/inter/            # Inter-Regular.ttf, Inter-Medium.ttf, Inter-SemiBold.ttf, OFL.txt
    └── kernel/
        ├── include/                # public headers, one per module (same names as .c)
        ├── arch/                   # x86_64 specifics
        │   ├── entry.asm           # _start: stack, SSE enable, call kmain
        │   ├── gdt.c gdt_flush.asm
        │   ├── idt.c isr_stubs.asm # 256 stubs, common stub with fxsave/fxrstor
        │   ├── pic.c               # 8259 remap/mask/EOI
        │   ├── lapic.c             # LAPIC MMIO, timer, LINT0 ExtINT
        │   ├── pit.c               # PIT ch2 one-shot for calibration
        │   ├── cpu.c               # cpuid, msr, cr0-4 helpers, tsc
        │   ├── io.h               # inb/outb/inw/outw/ind/outd, io_wait
        │   └── panic.c             # panic(): framebuffer panic screen + serial dump
        ├── boot/limine_req.c       # all Limine requests + markers, boot_info struct
        ├── lib/                    # string.c (memcpy/memset/memmove/memcmp/strlen/strcmp/strncpy), printf.c (kvsnprintf),
        │                           #   math.c (sqrtf, floorf, ceilf, fmodf, powf, cosf, acosf, fabsf, sinf, expf), ringbuf.h
        ├── log/serial.c klog.c     # COM1 + in-memory ring for the Terminal window
        ├── mm/pmm.c vmm.c heap.c   # bitmap PMM, page tables + PAT, heap (malloc/free/realloc/calloc)
        ├── time/timer.c rtc.c      # LAPIC 1 kHz tick, TSC time_us(), CMOS RTC wall clock
        ├── drivers/ps2.c           # i8042 controller + keyboard + mouse, event queue
        ├── input/keymap.c          # scancode set 1 → keycode → char (US layout, shift/caps)
        ├── acpi/tables.c           # RSDP/RSDT/XSDT/FADT/MADT parse, acpi_find_table(sig, idx)
        ├── acpi/laihost.c          # all laihost_* glue
        ├── acpi/lai_init.c         # lai namespace, EC, enable ACPI
        ├── power/battery.c battery_acpi.c battery_sim.c reboot.c
        ├── gfx/                    # surface.c draw.c rrect.c blur.c shadow.c gradient.c text.c font_inter.asm cursor.c blit.c color.h
        ├── anim/anim.c easing.c spring.c
        ├── ui/                     # scene.c compositor.c splash.c lock.c desktop.c wallpaper.c menubar.c battery_widget.c
        │                           #   dock.c window.c wm.c cursor_layer.c console.c about.c settings.c overlay.c theme.h
        ├── shell/commands.c        # command interpreter for the Terminal window
        └── kmain.c                 # init sequence + main loop
```

Build output: `v1/build/obj/**/*.o`, `v1/build/kernel.elf`, `v1/build/gzowo.iso`, `v1/build/iso_root/`.

## 2. Third-party dependencies — decision: vendor and pin

Everything in `third_party/` is committed to git. Justification: Jurek's builds must never depend on the network or on upstream changes; LAI is ~1 MB of C, Limine binaries ~1 MB, three Inter TTFs ~1 MB. `tools/fetch-deps.sh` is run once by the Coder (and again only to deliberately upgrade):

```
LIMINE_VER=12.8.0  # release asset limine-binary.tar.gz
curl -L "https://github.com/Limine-Bootloader/Limine/releases/download/v${LIMINE_VER}/limine-binary.tar.gz" | tar xz
  → copy limine.h BOOTX64.EFI limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin LICENSE + the host tool sources
  → build host tool: cd third_party/limine && make CC=cc     (Apple clang builds it; produces ./limine)
git clone https://github.com/managarm/lai third_party/lai && git -C third_party/lai checkout <PIN commit> && rm -rf .git
curl -L https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h -o third_party/stb/stb_truetype.h
curl -L https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip → extract extras/ttf/Inter-Regular.ttf, Inter-Medium.ttf, Inter-SemiBold.ttf and OFL.txt (LICENSE.txt)
```

Licenses: keep `third_party/limine/LICENSE` (BSD-2), `third_party/lai/LICENSE` (MIT), `third_party/fonts/inter/OFL.txt`, `third_party/stb/LICENSE` (text of the public-domain/MIT choice). The About window shows "Fonts: Inter (SIL OFL 1.1)".

Missing host tools: `brew install lld nasm xorriso qemu` (llvm is already installed). OVMF: `/usr/local/share/qemu/edk2-x86_64-code.fd` appears after installing qemu.

## 3. Toolchain and build

### 3.1 Compiler decision (SSE): ENABLED

stb_truetype and the animation/easing code use `float`. clang for x86-64 cannot compile float code without SSE (verified: `-mno-sse` errors). Decision:
- Compile the whole kernel **with SSE/SSE2** (baseline `-march=x86-64`, which is exactly SSE2; explicitly `-mno-avx -mno-avx2 -mno-mmx -mno-80387`).
- `entry.asm` enables SSE before any C runs: `CR0.EM=0, CR0.MP=1, CR4.OSFXSR=1, CR4.OSXMMEXCPT=1`. (Base revision ≥ 5 Limine clears these bits, so we must set them.)
- Interrupt safety: there are no threads, but ISRs interrupt SSE-using code. The common ISR stub does `fxsave` into a 512-byte, 16-aligned area on the interrupt stack and `fxrstor` before `iretq`. Cost ≈ 100 ns at 1 kHz — negligible. ISR handlers may then freely be normal C.
- Stack alignment: entry stack is aligned to 16 by us (`and rsp, -16`) before `call kmain`.
- Hot loops (blend, blur, blit) are written as plain C with `restrict` and simple inner loops; clang auto-vectorises with SSE2. Optional later: `movntdq` intrinsics in `blit.c` only (`#include <immintrin.h>` works freestanding with clang).

### 3.2 Flags (Makefile variables)

```
CC      ?= /usr/local/opt/llvm/bin/clang     # fallback: /usr/bin/clang (both verified for x86_64-unknown-elf)
LD      ?= /usr/local/opt/lld/bin/ld.lld     # or ld.lld on PATH after brew install lld
NASM    ?= nasm
CFLAGS  = --target=x86_64-unknown-elf -std=gnu11 -O2 -g -pipe \
          -ffreestanding -nostdlibinc -fno-stack-protector -fno-stack-check -fno-lto -fno-pic -fno-pie \
          -fno-builtin -fno-omit-frame-pointer -ffunction-sections -fdata-sections \
          -mno-red-zone -mcmodel=kernel -march=x86-64 -mno-avx -mno-avx2 -mno-mmx -mno-80387 \
          -Wall -Wextra -Wno-unused-parameter -MMD -MP \
          -Ikernel/include -Ithird_party/limine -Ithird_party/lai/include -Ithird_party/stb
LAI_CFLAGS = $(CFLAGS) -Wno-everything          # LAI is noisy under -Wall
NASMFLAGS  = -f elf64 -g -F dwarf -Wall
LDFLAGS    = -nostdlib -static -z max-page-size=0x1000 -z noexecstack --gc-sections -T linker.ld -m elf_x86_64
```
`-fno-builtin` is important: it stops clang from replacing our `memcpy` loops with calls to itself. clang still emits `memcpy/memset/memmove/memcmp` calls for struct copies → `lib/string.c` must always provide them (with `__attribute__((used))`).

Link: `$(LD) $(LDFLAGS) $(OBJ) -o build/kernel.elf`. No objcopy anywhere: Limine loads ELF directly; the font is embedded with NASM `incbin` (§9.6). `llvm-objcopy` exists if ever needed but is not used.

### 3.3 linker.ld (from the official Limine C template, entry renamed)

```
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)
PHDRS { limine_requests PT_LOAD; text PT_LOAD; rodata PT_LOAD; data PT_LOAD; }
SECTIONS {
    . = 0xffffffff80000000;
    .limine_requests : { KEEP(*(.limine_requests_start)) KEEP(*(.limine_requests)) KEEP(*(.limine_requests_end)) } :limine_requests
    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .text : { *(.text .text.*) } :text
    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .rodata : { *(.rodata .rodata.*) } :rodata
    .note.gnu.build-id : { *(.note.gnu.build-id) } :rodata
    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .data : { *(.data .data.*) } :data
    .bss : { *(.bss .bss.*) *(COMMON) } :data
    /DISCARD/ : { *(.eh_frame*) *(.note .note.*) }
}
```
Also export `__kernel_start`/`__kernel_end` symbols (add `PROVIDE(__kernel_start = .)` at the top and `PROVIDE(__kernel_end = .)` after .bss) for the VMM.

### 3.4 Limine requests (`boot/limine_req.c`) — base revision 6

```c
__attribute__((used, section(".limine_requests_start"))) static volatile uint64_t start_marker[] = LIMINE_REQUESTS_START_MARKER;
__attribute__((used, section(".limine_requests")))       static volatile uint64_t base_rev[] = LIMINE_BASE_REVISION(6);
__attribute__((used, section(".limine_requests"))) static volatile struct limine_framebuffer_request fb_req = { .id = LIMINE_FRAMEBUFFER_REQUEST_ID, .revision = 0 };
... memmap_request, hhdm_request, rsdp_request, executable_address_request, module_request (internal_module_count=0)
__attribute__((used, section(".limine_requests_end")))   static volatile uint64_t end_marker[] = LIMINE_REQUESTS_END_MARKER;
```
Use the struct/macro names exactly as they appear in the vendored `limine.h` (v12 uses "executable" naming: `limine_executable_address_request`, `LIMINE_MEMMAP_EXECUTABLE_AND_MODULES`). Check `LIMINE_BASE_REVISION_SUPPORTED(base_rev)` first thing in `kmain`; if false, `hcf()`.

Address conventions at base revision 6: all response pointers, the RSDP address, and module file addresses are **virtual (HHDM)**. Provide `boot_info` with both: `boot.rsdp_phys = (uintptr_t)rsdp_resp->address - hhdm` guarded by a helper `to_phys(addr) = addr >= hhdm ? addr - hhdm : addr` so the code also survives an older Limine that returns physical.

Machine state at entry (from PROTOCOL.md, rely on it): 64-bit long mode, paging on with the kernel at its higher-half address plus the HHDM, framebuffer mapped WC (PAT5), IF=0, CS=0x28, DS/ES/SS=0x30, ≥64 KiB stack in bootloader-reclaimable memory, no SSE guarantee, GDT/IDT are the bootloader's (must be replaced before we touch bootloader-reclaimable memory).

### 3.5 limine.conf (installed at `iso_root/boot/limine/limine.conf`)

```
timeout: 0
quiet: yes
interface_branding: Gzowo OS
interface_branding_colour: ffffff
term_background: 000000

/Gzowo OS
    protocol: limine
    path: boot():/boot/kernel.elf
```
`timeout: 0` boots instantly (hold a key during boot to get the menu; Limine still honours that). For debugging builds `make run-menu` copies a variant with `timeout: 3`.

### 3.6 ISO (`tools/make-iso.sh`, wraps the official recipe)

```
rm -rf build/iso_root && mkdir -p build/iso_root/boot/limine build/iso_root/EFI/BOOT
cp build/kernel.elf build/iso_root/boot/
cp limine.conf third_party/limine/{limine-bios.sys,limine-bios-cd.bin,limine-uefi-cd.bin} build/iso_root/boot/limine/
cp third_party/limine/BOOTX64.EFI build/iso_root/EFI/BOOT/
xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
   -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
   --protective-msdos-label build/iso_root -o build/gzowo.iso
third_party/limine/limine bios-install build/gzowo.iso
```
Result is hybrid: BIOS El Torito + UEFI El Torito + protective MBR; `dd`-able to USB and bootable via UEFI on the HP laptop (the EFI/BOOT/BOOTX64.EFI path is what the laptop firmware looks for). 

### 3.7 QEMU (`tools/run-qemu.sh`)

```
OVMF="$(brew --prefix)/share/qemu/edk2-x86_64-code.fd"
ACCEL=hvf   # --tcg switches to tcg (slower, for debugging with -d int)
qemu-system-x86_64 -M q35 -accel "$ACCEL" -cpu host -m 512M -smp 1 \
  -drive if=pflash,unit=0,format=raw,readonly=on,file="$OVMF" \
  -cdrom build/gzowo.iso -boot d \
  -serial stdio -no-reboot -no-shutdown \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -display cocoa,show-cursor=on
```
- `-cpu host` only with hvf; with tcg use `-cpu qemu64`.
- `--bios` variant drops the pflash line (Limine BIOS path) — checks the hybrid ISO.
- `--debug`: `-accel tcg -d int,cpu_reset -D build/qemu.log` (interrupt tracing only works meaningfully under TCG).
- `--res 1280x800` writes a temporary limine.conf with `resolution: 1280x800x32` and rebuilds the ISO; default leaves resolution to firmware (OVMF gives 1280x800 typically; the laptop gives 1920x1080).
- Serial output goes to the terminal; `-device isa-debug-exit` lets `outw(0xf4, code)` terminate QEMU with exit status `(code<<1)|1` — used by `make test` (kernel boots, runs self-checks, exits 0x10 → QEMU exit 33 = pass).

### 3.8 write-usb.sh (safety)

Requires exactly one argument `/dev/diskN`. Steps: `diskutil list` printed in full; then `diskutil info "$DISK"` summary (name, size, `Removable Media`, `Device Location: External`); refuses if not External/Removable or if it is the boot volume; prints "Type YES to write gzowo.iso to $DISK (this ERASES it)"; only on exact `YES`: `diskutil unmountDisk "$DISK"`, `sudo dd if=build/gzowo.iso of="/dev/r${DISK#/dev/}" bs=4m status=progress`, `sync`, `diskutil eject`. Never runs without the argument.

## 4. Kernel core (M1) — order and exact design

### 4.1 `arch/entry.asm`
`_start`: `cli`; set up SSE (CR0/CR4 bits above); `mov rsp, kernel_stack_top` (own 64 KiB `.bss` stack, 16-aligned); `xor rbp, rbp`; `call kmain`; `hlt` loop. Keeping our own stack means we don't depend on bootloader-reclaimable memory later.

### 4.2 Serial (`log/serial.c`) — first thing in kmain
COM1 0x3F8, 115200 8N1, poll TX-empty. `klog(fmt, ...)` → `kvsnprintf` (supports `%s %d %u %x %llx %p %c %%`, width/zero-pad; `%f` with fixed 2 decimals for battery/fps) → serial AND `klog_ring` (64 KiB text ring read by the Terminal window; `klog_ring_lines(cb)`). Levels: `KLOG_INFO/WARN/ERR` prefixes `[ok]/[warn]/[err]`.

### 4.3 GDT/TSS (`arch/gdt.c`)
Entries: null, kernel code 0x08, kernel data 0x10, (user code/data slots 0x18/0x20 reserved, unused), TSS 0x28 (16-byte). TSS: RSP0 = kernel stack top, IST1 = separate 16 KiB stack for double fault (vector 8 uses IST1). `gdt_flush.asm` reloads segments via far return and `ltr`.

### 4.4 IDT + exceptions (`arch/idt.c`, `arch/isr_stubs.asm`)
256 gates. NASM macros generate `isr0..isr255` (push dummy error code where the CPU doesn't). Common stub: push all GPRs, `sub rsp,512; and rsp,-16; fxsave [rsp]`, pass `struct regs*` in `rdi` to `isr_dispatch(regs)`, restore. `struct regs { r15..rax, int_no, err_code, rip, cs, rflags, rsp, ss }` (document exact order = push order). Exceptions 0–31: `panic_exception(regs)` dumps all registers, CR2, CR3, and a 16-entry stack trace via frame pointers (we keep `-fno-omit-frame-pointer`). Handler table `irq_handlers[256]` with `idt_register(vec, fn)`.

### 4.5 PIC (`arch/pic.c`)
Remap to 0x20–0x2F, mask all except IRQ1 (kbd), IRQ2 (cascade), IRQ12 (mouse); IRQ0 stays masked (PIT is only used in polled mode). `pic_eoi(irq)`. Spurious IRQ7/15 handling.

### 4.6 PMM (`mm/pmm.c`)
Bitmap over physical pages up to highest usable address (from the memmap). Bitmap stored in the largest usable region (via HHDM). Mark usable regions free; everything else used. Bootloader-reclaimable stays "used" for v1 (simplicity; it's a few MiB). API: `pmm_alloc_page()` (returns phys, zeroed via HHDM), `pmm_alloc_pages(n)` contiguous (first-fit scan; needed for big surfaces up to 8 MiB → use `pmm_alloc_pages` for backbuffer), `pmm_free_pages`, `pmm_stats(&total,&used)`. Serial prints memmap table.

### 4.7 VMM (`mm/vmm.c`) — own page tables with PAT
- Set PAT MSR (0x277) to Limine's layout so index 5 = WC: value `0x0007010500070406` (PAT0 WB, 1 WT, 2 UC-, 3 UC, 4 WP, 5 WC, 6 UC-, 7 UC).
- Build PML4: (a) kernel image: map `[phys_base, phys_base+size)` → `virtual_base` from the executable address response, using the PHDR permissions (text RX, rodata R, data RW; NX on non-text since EFER.NXE is set by Limine); (b) HHDM: map every memmap entry except BAD_MEMORY at `hhdm + phys` with 2 MiB pages, WB, RW, NX; framebuffer entries (`LIMINE_MEMMAP_FRAMEBUFFER`) with the WC PAT index (2 MiB PDE: bit 12 = PAT, PCD=0, PWT=1 → index 5); (c) additionally map the 0–4 GiB physical window in the HHDM as UC for MMIO? No — instead provide `vmm_map_mmio(phys, len)` returning `hhdm + phys` after mapping 4 KiB pages with PCD=1 (UC), used for LAPIC (0xFEE00000), HPET, IOAPIC, and by `laihost_map`.
- `vmm_switch()` writes CR3; from then on bootloader mappings are gone. The framebuffer pointer we use stays `hhdm + fb_phys` (fb_phys = to_phys(fb->address)).
- Verification: after switching, write a test pattern to the framebuffer and read back a heap page; check `klog("[ok] vmm: cr3=%llx")`.

Rationale for WC: on the real laptop the GOP framebuffer is VRAM behind a PCIe BAR; UC writes would make a full-frame blit take ~100 ms; WC batches into 64-byte bursts and gives GB/s. Blits must therefore be **sequential forward writes of whole rows** (memcpy-style, 8-byte or 16-byte stores), never read-modify-write on the framebuffer, never scattered single-pixel pokes. All reads happen from the RAM backbuffer only.

### 4.8 Heap (`mm/heap.c`)
Free-list allocator with size classes: small blocks (16..2048 B) from slab pages (per-class free lists, header-less with page-header lookup by page alignment), large blocks (>2048 B) directly from `pmm_alloc_pages` with a 16-byte header. API: `kmalloc, kfree, krealloc, kcalloc`, `kmalloc_aligned(size, 16/64)`, `heap_stats()`. All returns 16-byte aligned (SSE). Heap grows on demand; no fixed limit. Debug: `HEAP_POISON` fills freed memory with 0xDE in debug builds. LAI's `laihost_free(ptr, size)` gives size — ignore it. Also provide `malloc/free/realloc` as thin aliases only if stb requires them (we set `STBTT_malloc(x,u)` to `kmalloc(x)` instead).

### 4.9 Timers (`time/timer.c`, `arch/lapic.c`, `arch/pit.c`, `arch/cpu.c`)
- LAPIC base from MADT (fallback MSR 0x1B & ~0xFFF, typically 0xFEE00000), mapped UC. Enable via spurious vector reg (0xF0 = 0x1FF). Set LVT LINT0 = ExtINT (0x700) so legacy PIC IRQs are delivered, LINT1 = NMI (0x400).
- Calibrate: PIT channel 2 one-shot for 10 ms polled via port 0x61 bit 5 (gate bit 0 on, speaker bit 1 off); during it count LAPIC timer ticks (divider 16, initial 0xFFFFFFFF) and TSC delta → `lapic_hz`, `tsc_hz`. Repeat 3× and take the median. Log both.
- LAPIC timer periodic at 1000 Hz on vector 0x40: ISR increments `ticks_ms`, calls `ps2_poll_drain()` (§5.3) and `anim_tick_hook` (none in v1). EOI.
- `time_us()` = TSC-based (`(rdtsc - tsc0) * 1000000 / tsc_hz` using 128-bit mul via `__uint128_t`), `time_ms()` = `ticks_ms`. Invariant TSC exists on Ryzen 5800H and QEMU; if CPUID says no invariant TSC, `time_us()` falls back to `ticks_ms*1000 + LAPIC current-count interpolation`.
- `sleep_ms(n)` = `hlt` loop on `ticks_ms`; `udelay(us)` = TSC spin (used by i8042, LAI).

### 4.10 RTC (`time/rtc.c`)
CMOS read with update-in-progress check, BCD/binary and 12/24h handling from status register B, century from FADT `century` field if nonzero. `rtc_read(struct datetime*)` once at boot; afterwards wall clock = boot datetime + `time_ms()` (re-synced from CMOS every 60 s). Weekday computed (Zeller). Time zone: none in v1 (RTC assumed local; QEMU `-rtc base=localtime` in run script).

**M1 verified when:** serial shows GDT/IDT/PIC/PMM/VMM/heap/LAPIC/RTC `[ok]` lines, a deliberate `int 3` prints a register dump and continues, `sleep_ms(1000)` measured against wall clock (`-rtc`) is 1 s ± 5%, and `kmalloc`/`kfree` of 10 000 mixed blocks with checksums passes a self-test (`make test` exits 33).

## 5. Input (M2)

### 5.1 i8042 (`drivers/ps2.c`)
Init sequence (each wait ≤ 100 000 polls of status 0x64 with `udelay(10)`, log timeouts, continue):
1. Disable ports: `0xAD`, `0xA7`. Flush output buffer (read 0x60 while status bit0).
2. Read config (`0x20`); clear bits 0,1 (IRQs), keep bit 6 (translation → scancode set 1); write (`0x60`, cfg). Remember whether bit 5 was set (dual-channel hint).
3. Self-test `0xAA` → expect `0x55`; re-write config after it (some controllers reset).
4. Dual-channel probe: `0xA8`, read config, bit5 clear ⇒ dual; then `0xA7` again.
5. Interface tests `0xAB` (port 1), `0xA9` (port 2) → 0x00 means ok.
6. Enable port 1 (`0xAE`), port 2 (`0xA8` if dual); set config bits 0,1 (and keep 6).
7. Keyboard: `0xFF` reset → ACK 0xFA then 0xAA (with timeout); `0xF4` enable scanning. Set LEDs off.
8. Mouse (only if dual & port-2 test passed): write via `0xD4` prefix: `0xFF` → 0xFA,0xAA,0x00; `0xF6` set defaults; try IntelliMouse: `0xF3 0xC8`, `0xF3 0x64`, `0xF3 0x50`, `0xF2` → id 3 ⇒ 4-byte packets with wheel; `0xF3 0x64` (100 Hz), `0xF4` enable streaming. If any step times out → `mouse_present=false`, log `[warn] ps2: no mouse`; UI then hides the mouse-cursor until arrow keys move it.
IRQ1 and IRQ12 handlers both call `ps2_handle_byte(byte, from_aux)` where `from_aux` = status bit 5. 

### 5.2 Keyboard decoding (`input/keymap.c`)
Scancode set 1: `0xE0` prefix state machine; break bit 0x80. Tables → `enum key { KEY_A.., KEY_ENTER, KEY_ESC, KEY_TAB, KEY_LEFT.., KEY_F1.., KEY_LSHIFT, KEY_LCTRL, KEY_LALT, KEY_LGUI, ... }`. Modifier state (shift L/R, ctrl, alt, gui/cmd, caps). `struct input_event { enum {EV_KEY_DOWN, EV_KEY_UP, EV_KEY_REPEAT, EV_MOUSE_MOVE, EV_MOUSE_BUTTON, EV_MOUSE_WHEEL} type; uint16_t key; uint32_t ch /* unicode or 0 */; uint8_t mods; int16_t dx, dy, wheel; uint8_t buttons; }`. US QWERTY with shift/caps translation. Key repeat is generated by the UI layer (500 ms delay, 30 Hz) from held-key state so it works even if the hardware repeat is different.

### 5.3 Mouse packets
3/4-byte packet parser with sync check (byte0 bit3 must be 1 else resync). Accumulate `dx, dy` (dy inverted), buttons L/R/M, wheel. Movement applied by the UI with acceleration `speed = 1.0 + min(|v|,20)/20*1.5`.

### 5.4 Event queue + fallback drain
`input_queue` is a 256-entry ring (single producer in ISR, single consumer in main loop; head/tail `volatile`). `ps2_poll_drain()` is called from the 1 kHz tick: `while (inb(0x64) & 1) ps2_handle_byte(inb(0x60), status & 0x20)`. This means the keyboard and mouse **work even if IRQ1/IRQ12 never fire on the laptop** (PIC routing quirk) — the tick polls at 1 kHz which is faster than PS/2 byte rate. Both paths run with IF=0 so there is no reentrancy.

**M2 verified when:** serial prints decoded key names and mouse deltas; `make run` with `-serial stdio` shows `KEY_DOWN A` etc.; unplugged-mouse scenario tested with `-M q35 -global i8042.mouse=false`? (not a QEMU option — instead test by temporarily forcing `mouse_present=false`) shows graceful `[warn]` and boots.

## 6. ACPI tables + LAI (M6, but tables part is needed in M1 for the LAPIC address)

### 6.1 `acpi/tables.c`
RSDP from Limine (validate signature + checksum; revision ≥ 2 ⇒ XSDT else RSDT). `acpi_find_table("FACP"/"APIC"/"HPET"/"SSDT", index)` iterates entries via HHDM (tables may live above 4 GiB on real HW — HHDM covers ACPI_RECLAIMABLE/NVS regions because we mapped all memmap entries). Special-case `"DSDT"` → FADT `X_Dsdt` (or `Dsdt`). MADT: LAPIC address (+ override entry type 5), list of I/O APICs and ISOs (logged, kept for a possible IOAPIC switch). FADT: `SMI_CMD`, `ACPI_ENABLE`, `PM1a_CNT`, `ResetReg/ResetValue`, `Century`, `IAPC_BOOT_ARCH` flags (bit 1 "8042 present" — log it; on the HP, firmware may say no 8042 even though the internal keyboard is PS/2 — we still probe).

### 6.2 LAI build
Compile `third_party/lai/core/*.c helpers/*.c drivers/*.c` with `LAI_CFLAGS` into `build/liblai.a` (`llvm-ar rcs`) or just link the objects. LAI requires from us only `memcpy/memset/memcmp/strlen/strcmp` equivalents (it has its own `core/libc.c` wrappers calling `laihost_*`? — check `core/libc.h`: it defines `lai_memcpy` etc. as its own implementations; if it declares externs for `memcpy`, ours satisfy them) and the `laihost_*` functions.

### 6.3 `acpi/laihost.c` glue (all signatures confirmed from `lai/host.h`)
```
void  laihost_log(int level, const char *msg)      → klog (LAI_WARN_LOG→[warn])
void  laihost_panic(const char *msg)               → panic()
void *laihost_malloc(size_t)                        → kmalloc
void *laihost_realloc(void *p, size_t new, size_t old) → krealloc
void  laihost_free(void *p, size_t)                 → kfree
void *laihost_map(size_t phys, size_t count)        → if inside HHDM-mapped memmap → hhdm+phys, else vmm_map_mmio(phys,count)
void  laihost_unmap(void *, size_t)                 → no-op
void *laihost_scan(const char *sig, size_t index)   → acpi_find_table (handles "DSDT")
in/out b/w/d                                        → io.h
pci_read/write b/w/d (seg,bus,slot,fn,off)         → legacy 0xCF8/0xCFC mechanism (seg must be 0; ignore MCFG in v1)
void  laihost_sleep(uint64_t ms)                    → sleep_ms
uint64_t laihost_timer(void)                        → time_us()*10  (100 ns units)
laihost_sync_wait/wake                              → not provided (weak; single-threaded)
```

### 6.4 `acpi/lai_init.c`
1. `lai_set_acpi_revision(rsdp->revision)`; `lai_create_namespace()` (parses DSDT + all SSDTs; needs a healthy heap — expect 1–4 MB on the laptop).
2. Embedded Controller (needed on real laptops — battery `_BST` reads EC opregion fields): iterate namespace, for devices matching `PNP0C09` allocate `struct lai_ec_driver`, call `lai_init_ec(node, drv)`; if an `ECDT` table exists call `lai_early_init_ec(drv)` before namespace creation. Then register the opregion override for that node — the Coder must read `third_party/lai/drivers/ec.c` and `include/lai/core.h` for the exact registration call (`lai_ns_override_opregion`-style API exists in current LAI; if the vendored commit differs, follow its header).
3. `lai_enable_acpi(0)` (mode 0 = PIC, matching our interrupt setup; writes ACPI_ENABLE to SMI_CMD and waits for SCI_EN, evaluates `_PIC`). Wrap the whole LAI init in a "try" with a 2 s timeout budget logged; any LAI failure sets `acpi_ok=false` and the OS continues with the simulated battery. SCI interrupt (IRQ9) stays masked in v1; we poll the battery.
4. Battery/AC discovery: `lai_variable_t pnp; lai_eisaid(&pnp, "PNP0C0A"); struct lai_ns_iterator it = LAI_NS_ITERATOR_INITIALIZER; while ((node = lai_ns_iterate(&it))) if (lai_check_device_pnp_id(node, &pnp, &state) == 0) → battery node`. Same for `ACPI0003` (AC adapter).

### 6.5 Battery evaluation (`power/battery_acpi.c`)
- `_STA` (via `lai_resolve_path(bat, "_STA")` + `lai_eval`): bit 4 ⇒ battery present.
- `_BIX` (prefer) else `_BIF`: package; `_BIF` indices: 0 power unit, 1 design cap, 2 last full cap; `_BIX`: 0 revision, 1 unit, 2 design, 3 last full. Read via `lai_obj_get_pkg(&pkg, idx, &elem)` + `lai_obj_get_integer`. Cache last-full capacity (re-read every 5 min).
- `_BST` every 2 s: index 0 state (bit0 discharging, bit1 charging, bit2 critical), 1 rate, 2 remaining, 3 voltage. `percent = clamp(remaining*100/last_full)`; if `last_full==0` use design cap; if remaining is 0xFFFFFFFF (unknown) keep the last value.
- AC: `_PSR` of the `ACPI0003` device: 1 = online.
- `lai_var_finalize` on every variable; `lai_init_state`/`lai_finalize_state` per evaluation.

### 6.6 `power/battery.c` interface
```c
enum battery_source { BAT_SRC_NONE, BAT_SRC_ACPI, BAT_SRC_SIMULATED };
struct battery_state { bool present; int percent; bool charging; bool ac_online; bool low /* <20 */; bool critical /* <5 */; enum battery_source source; uint64_t updated_ms; };
void battery_init(void);            // tries ACPI; if no PNP0C0A device with _STA present → battery_sim_init()
void battery_poll(void);            // called from the main loop; does work at most every 2000 ms
void battery_get(struct battery_state *out);
```
`battery_sim.c`: starts at 87 %, drains 1 % every 8 s while discharging; F9 toggles AC (charging refills 1 % / 3 s, stops at 100); Shift+F9 sets 15 % (low-battery visuals). Settings window exposes drain speed. `source=SIMULATED` is shown in the menubar tooltip/About as "(simulated)".

### 6.7 Reboot (`power/reboot.c`)
Order: (1) if LAI ok: `lai_acpi_reset()`; (2) FADT reset register write (I/O space case: `outb(reset_reg.address, reset_value)`, memory case via HHDM); (3) i8042 `0xFE` pulse after waiting input buffer empty; (4) triple fault (`lidt` with zero limit + `int3`). Log each attempt.

**M6 verified when:** in QEMU: `[ok] lai: namespace 2xx nodes`, `[info] battery: no PNP0C0A → simulated`; `battery` command prints the struct; `reboot` restarts QEMU (with `-no-reboot` QEMU exits instead — the script prints "reboot requested"). Fallback if LAI fails to build in freestanding mode (documented plan B): keep `acpi/tables.c` (FADT reset still works), compile out `lai_init.c`/`battery_acpi.c` with `-DGZOWO_NO_LAI`, and use only the simulated battery; About window says "Battery: simulated (no AML interpreter)". A plan C, if LAI works in QEMU but misbehaves on the laptop, is swapping in uACPI (same host-glue shape); not scheduled for v1.

## 7. Graphics library (`gfx/`, M3)

### 7.1 Surfaces and colour model
`struct surface { uint32_t *px; int w, h; int stride /* in pixels */; bool owns; }`. Pixel format everywhere: **premultiplied ARGB8888** (`A<<24|R<<16|G<<8|B`), little-endian, which equals the common GOP/QEMU XRGB layout for opaque pixels. Premultiplied ⇒ `dst = src + dst * (255 - src.a) / 255` with no division for the source; batch two channels at once (`0x00FF00FF` masks) for speed. `color.h`: `rgba(r,g,b,a)` returns premultiplied; `lerp_color`; `with_alpha`.

The framebuffer format is checked at boot: if `bpp==32` and masks are R@16,G@8,B@0 → fast path (memcpy rows). Otherwise `blit.c` converts per row using the Limine masks (slow generic path, logged as warning). Anything not 32 bpp → panic screen "unsupported framebuffer" (unrealistic for GOP).

### 7.2 Backbuffer + blit strategy (`gfx/blit.c`)
- `backbuffer` = surface `fb.w × fb.h` in RAM (pmm contiguous, 16-byte aligned rows). All drawing targets it. Zero reads from the framebuffer ever.
- `gfx_present(const rect *dirty, int n)`: for each dirty rect, for each row: copy `w*4` bytes from backbuffer to `fb + y*pitch + x*4` with an 8-byte/16-byte forward copy (`rep movsq` or SSE2 `movdqa`/`movntdq` on 16-byte aligned spans; unaligned heads/tails via 32-bit stores). Rows are written top to bottom, left to right. **pitch is always taken from Limine** (`fb->pitch`), never `w*4`.
- Tearing: no vsync exists; scanout can interleave with our copy. Mitigations: (1) copy at full speed (whole frame in ~2–4 ms on real HW with WC), (2) copy dirty rects only, (3) write rows top-to-bottom, which matches scanout direction so any tear is a single horizontal seam rarely visible. This is the accepted v1 trade-off ("no visible tearing" in practice; true vsync would need a GPU driver).
- Dirty-rect policy: the compositor accumulates up to 16 rects per frame; overlapping/adjacent rects are merged; if the union covers > 60 % of the screen, a single full-frame present is done.

### 7.3 Primitives (`gfx/draw.c`)
`gfx_clip_push(rect)/pop` (clip stack, all primitives clip); `fill_rect(s, rect, color)` (fast path for alpha 255 = row fill with `uint64_t` pairs); `blend_surface(dst, src, x, y, alpha)`; `blit_scaled(dst, src, dst_rect, alpha)` (bilinear, used for window open/close scale animation and blur upsampling); `draw_line` (Wu AA or 1-px Bresenham for v1), `fill_circle_aa` (distance-based coverage), `draw_hline/vline`.

### 7.4 Rounded rectangles (`gfx/rrect.c`)
`fill_rrect(s, rect, radii[4], color)` and `stroke_rrect(..., width)`: interior rows filled via `fill_rect`; the four corner squares are rasterised per pixel with coverage `cov = clamp(r + 0.5 - dist(px_center, corner_center), 0, 1)` (analytic circle AA, good to ~1/255). Per-corner radius supports macOS-style windows (top corners rounded, bottom too) and menubar (0). Coverage multiplies the premultiplied colour before blending.

### 7.5 Gradients (`gfx/gradient.c`)
`fill_linear_gradient(s, rect, angle_deg, stops[], n)` with up to 8 stops; per-row precomputation; optional ordered dithering (4×4 Bayer, ±1 LSB) to avoid banding on the wallpaper. `fill_radial_glow(s, cx, cy, radius, color)` (used for the wallpaper blobs, falloff = smoothstep).

### 7.6 Blur (`gfx/blur.c`) — translucency strategy
`blur_region(dst_surface, src_surface, rect, radius, downscale)`: (1) downsample the rect by `downscale` (4 for menubar/dock, 2 for window vibrancy) with box averaging; (2) three passes of a separable box blur (approximates Gaussian, radius `r/downscale`) using running sums — O(pixels), independent of radius; (3) bilinear upscale into a cached surface. Cost at 1080p: menubar 1920×28 → 480×7 (trivial); dock ~ 900×80 → 225×20 (trivial); a 900×600 window at ÷2 → 450×300, ~0.4 ms. Rules for 60 fps: blur sources are only re-computed when the region's dependencies changed (the compositor passes a `content_version` for the area behind the element: wallpaper version + ids/positions of windows intersecting the region). Static desktop ⇒ zero blur work per frame.

### 7.7 Shadows (`gfx/shadow.c`)
Nine-slice shadow tiles: `shadow_get(radius, blur, alpha)` renders once a `(2*(radius+blur)+1)²` alpha tile (rounded square, box-blurred ×3), caches it (≤ 16 entries), and `draw_shadow(s, rect, radii, blur, offset_y, alpha)` stretches the middle strips as rows/columns. Cost per window per frame ≈ fill of the shadow band only. Shadow is drawn only outside the window rect (skip the interior).

### 7.8 Text (`gfx/text.c`, `gfx/font_inter.asm`) — decision: stb_truetype + Inter
- Embed with NASM: `section .rodata; global font_inter_regular, font_inter_regular_end; font_inter_regular: incbin "third_party/fonts/inter/Inter-Regular.ttf"; font_inter_regular_end:` (same for Medium, SemiBold). Assembled with `nasm -f elf64 -I.` from `v1/`. No objcopy. C side: `extern const uint8_t font_inter_regular[], font_inter_regular_end[];`.
- `#define STB_TRUETYPE_IMPLEMENTATION` in exactly one file with: `STBTT_malloc(x,u) kmalloc(x)`, `STBTT_free(x,u) kfree(x)`, `STBTT_assert(x) kassert(x)`, `STBTT_ifloor/iceil` via our `floorf/ceilf`, `STBTT_sqrt sqrtf` (`__builtin_sqrtf` → `sqrtss`), `STBTT_pow powf`, `STBTT_fmod fmodf`, `STBTT_cos/acos` from `lib/math.c` (polynomial approximations; accuracy 1e-4 is plenty), `STBTT_fabs fabsf`, `STBTT_strlen/memcpy/memset` ours. Disable rasterizer v1? No: use the default v2 (AA, signed-area). `STBTT_STATIC`.
- Font faces: `FONT_REGULAR, FONT_MEDIUM, FONT_SEMIBOLD`. Sizes used (px): 11, 12, 13, 14, 17, 20, 28, 72 (clock). `struct font { stbtt_fontinfo info; float scale_for[size]; int ascent, descent, line_gap; }`.
- Glyph cache: hash map keyed `(face, size_px, codepoint)` → `{ uint8_t *cov; int w, h, x_off, y_off; float advance; }`; 4096-entry open-addressing table; never evicted in v1 (ASCII × 8 sizes × 3 faces ≈ 2 300 glyphs, ≈ 2 MB). Warm-up: rasterise printable ASCII for all (face, size) pairs during the splash (progress bar advances per face).
- `text_draw(s, face, size, x, y_baseline, color, utf8)` blends 8-bit coverage × premultiplied colour; kerning via `stbtt_GetCodepointKernAdvance`; positions rounded to integer pixels (no subpixel in v1, sharper on 1080p). `text_measure(face,size,str,&w,&h)`. UTF-8 decoder handles the few non-ASCII glyphs we might use (•, °, →).
- Early/panic text: `gfx/font8x8.c` — the public-domain `font8x8_basic` (dhepper) array, drawn 2× scaled; used by the panic screen and by `gfx_debug_print` before the heap exists.

### 7.9 Cursor sprite (`gfx/cursor.c`)
Procedural macOS-style arrow: polygon points at 1× (`(0,0),(0,16),(4,12),(7,19),(10,18),(7,11),(12,11)`), rasterised once at init into a 24×24 ARGB surface using a signed-distance-to-polygon per pixel (brute force over edges; 576 px × 7 edges) → black fill with 1 px white outline (coverage from the SDF at two offsets) and a blurred 40 % shadow offset (1,2). Scaled ×1.5 at ≥1440p by rasterising at that size. Hotspot (0,0). Also a "hand" and "text I-beam" are out of scope.

**M3 verified when:** a test scene (`GZOWO_GFX_TEST` build flag) shows: gradient background, 4 rounded rects with different per-corner radii and alpha, blurred strip, shadowed card, "Gzowo OS" in Inter SemiBold 72 px and a paragraph at 13 px, the cursor sprite; screenshot compared by eye; `fps` printed to serial ≥ 200 for the static scene at 1280×800 under HVF.

## 8. Animation system (`anim/`, M4)

- `easing.c`: `ease_linear, ease_out_cubic, ease_in_out_cubic, ease_out_quint, ease_out_back` (float t→float).
- `anim.c`: `struct tween { float *target; float from, to; uint32_t start_ms, dur_ms; easing_fn ease; void (*on_done)(void*); void *ud; bool active; }`; pool of 128; `anim_to(float *v, float to, ms, ease)` (retargets an existing tween on the same variable, starting from the current value — makes animations interruptible), `anim_cancel(v)`, `anim_update(now_ms)` called once per frame, `anim_any_active()`.
- `spring.c`: `struct spring { float x, v, target, stiffness, damping; }`; `spring_step(s, dt)` semi-implicit Euler with `dt` sub-stepped at 4 ms; presets: `SPRING_SNAPPY (k=400, c=30)`, `SPRING_SOFT (k=170, c=22)`. Used for dock magnification, window drag catch-up, cursor smoothing (optional).
- Timeline helper: `timeline_t` = array of `{delay_ms, fn}` fired once when elapsed (for splash sequencing).
- Frame pacing (in `kmain` main loop): target `FRAME_US = 16667`.
  ```
  next = time_us();
  loop: now = time_us();
        if (now < next) { hlt(); continue; }             // LAPIC 1 kHz tick wakes us; ≤1 ms latency
        dt = min(now - last, 50000); last = now;
        input_drain(); anim_update(); ui_update(dt); ui_render(); gfx_present(dirty)
        next += FRAME_US; if (now - next > 3*FRAME_US) next = now;   // frame skip: resync instead of catching up
  ```
  When nothing is dirty (no anim, no input, clock unchanged) `ui_render` is skipped entirely and the loop just `hlt`s → the idle CPU sits in `hlt` (important for laptop heat/fan and battery).
- FPS/heap overlay (`ui/overlay.c`, toggled with F12): frames per second (1 s window), frame time ms (avg/max), dirty area %, heap used/free, PMM used, blur cache hits, input queue depth.

**M4 verified when:** splash: wordmark fades in over 600 ms, progress bar eases through the real init steps (font warm-up, LAI, PS/2), crossfades to the lock screen; lock screen: blurred wallpaper, 72 px clock updating each minute, date line, pulsing "Press any key" (sine on alpha, 1.6 s period); any key → 400 ms transition (lock content slides up and fades; desktop scales 1.04→1.0). Serial FPS ≥ 60 during transitions in HVF at 1280×800.

## 9. UI shell (`ui/`, M4–M5)

### 9.1 Architecture decision: retained scene state + immediate-mode drawing
State (windows, dock items, cursor, battery) lives in plain structs. Every frame, for every dirty rect, the compositor draws layers back-to-front into the backbuffer with the clip set to that rect. There is no widget tree, no invalidation graph, no event bubbling machinery — the simplest thing an AI coder can keep correct. Dirty rects are produced by the objects that change (`ui_invalidate(rect)`): a moving cursor invalidates old+new sprite rects, an animating window invalidates its bounding rect (with shadow), the clock invalidates its text rect, the battery widget its own rect, etc. Full-screen invalidation during scene transitions.

### 9.2 Scene state machine (`ui/scene.c`)
`enum scene { SCENE_SPLASH, SCENE_LOCK, SCENE_DESKTOP }` + transition state `{ from, to, t (0..1) }`. Each scene has `update(dt)`, `draw(clip)`, `on_event(ev)`. During a transition both scenes draw (into two temporary full-screen surfaces cached from the last frame) and the compositor blends. SPLASH → LOCK: crossfade 500 ms. LOCK → DESKTOP: lock slides up (translate −h·t, alpha 1−t, ease-in-out) over desktop (scale 1.04→1.0, ease-out).

### 9.3 Compositor layers (`ui/compositor.c`), bottom to top on DESKTOP
1. Wallpaper (cached surface, `wallpaper.c`: diagonal gradient #1a1b2e → #3b2a5a → #d46a5b-ish warm accent with three radial glows; Bayer dithered; regenerated on resolution only; the UI/UX agent owns the palette in `theme.h`).
2. Windows (z-ordered; each window is an offscreen surface `w×h` redrawn only when its `dirty` flag is set; composited with scale/alpha for open/close; shadow drawn first).
3. Dock (blur of what's beneath, cached by content version; rounded translucent panel; icons with magnification/bounce).
4. Menubar (28 px at scale 1; blur cached; 70 % white/dark tint; "Gzowo OS" in Medium 13 px left; clock right; battery widget right of clock).
5. Overlay (FPS/heap, optional).
6. Cursor (drawn last; always invalidated on move).

### 9.4 Theme (`ui/theme.h`) — the file the UI/UX agent edits
Constants: colours (menubar tint, window bg, text primary/secondary, accent, traffic lights #ff5f57/#febc2e/#28c840), radii (window 12, dock 20, buttons 6), shadow params (window: blur 24, offset 12, alpha 0.45), font sizes, dock icon size (56), magnification (max 1.5, sigma 1.4 icons), durations (window open 260 ms, close 180 ms, dock bounce 600 ms, lock transition 420 ms), `UI_SCALE` computed as `height >= 1000 ? 1.25f : 1.0f` (all px constants multiplied at init).

### 9.5 Window manager (`ui/window.c`, `ui/wm.c`)
```c
struct window { int id; char title[48]; float x, y; int w, h; float scale, alpha; enum {WIN_OPENING, WIN_OPEN, WIN_CLOSING, WIN_CLOSED} state;
  struct surface *content; bool dirty; int z; bool focused;
  void (*draw)(struct window*, struct surface*); bool (*on_event)(struct window*, const struct input_event*); void *ud; };
```
API: `wm_open(id/factory)` (if already open → focus + bounce dock icon), `wm_close(w)`, `wm_focus(w)`, `wm_bring_to_front`, `wm_hit_test(x,y)` (topmost first: traffic lights → titlebar drag region → content). Drag: on mouse-down in the 36 px titlebar, `dragging=w, grab offset`; on move, set `x,y` directly (no spring, exact under the cursor; clamp so ≥ 40 px stays on screen). Traffic lights: close (red) works, yellow/green are drawn but no-op in v1 (hover brightens). Keyboard: `Cmd/Alt+W` or `Esc` closes focused window, `Cmd/Alt+Tab` cycles focus, arrow keys with `Cmd/Alt` move the focused window by 20 px. Window chrome (titlebar, title centered in Medium 13, separator, rounded 12 px, 1 px inner highlight) is drawn by `window.c` into the content surface; the window's `draw` callback draws only the client area. Open animation: `scale 0.92→1.0` ease-out-back(lite), `alpha 0→1` 260 ms; close: reverse, 180 ms, `on_done → WIN_CLOSED` and surface freed.

### 9.6 Dock (`ui/dock.c`)
Items (5): Files (opens a "Coming soon" tiny window), Terminal, About, Settings, Power (opens a small dialog: "Restart / Cancel"). Each: `{ name, icon_draw(surface,size), window_factory, scale (spring), bounce_phase }`. Icons are procedural rounded-square tiles with a two-stop gradient + a simple glyph (`>_` text for Terminal, `i` for About, gear = circle + 8 ticks, power = arc + line, folder = two rounded rects). Magnification: for pointer x over the dock, `target_scale_i = 1 + (MAG-1)·exp(-(d_i/σ)²)`, where `d_i` is in icon units; springs make it fluid; layout re-flows around scaled icons each frame (dock width animates). Keyboard: `Tab` focuses the dock (a selection ring), `←/→` move selection (with the same magnification centred on the selected item), `Enter` launches, `Esc` unfocuses. Launch bounce: `y_off = -|sin(π·t)|·22·(1−t)` for 600 ms, twice. Running indicator: 4 px dot under the icon while its window is open.

### 9.7 Menubar + battery widget (`ui/menubar.c`, `ui/battery_widget.c`)
Clock "Mon 7 Sep  14:05" (Medium 13) updated when the minute changes (`ui_invalidate` on change). Battery widget: 25×12 rounded-rect body (r=3, 1.5 px stroke @ 50 % white) + 2×5 nub; fill rect width animates with `anim_to(&fill_w, percent/100*body_w, 600 ms, ease_out_cubic)`; colour: white (>20), `#ff453a` (≤20), `#30d158` while charging; when `charging` a bolt polygon (7-point) is drawn over the body in black-with-white-outline; "87 %" text right; if `source==SIMULATED` a tiny "SIM" caption appears only in the overlay/About (not in the bar — minimalism). On percent change the whole widget rect is invalidated; a low-battery transition also pulses the fill alpha once.

### 9.8 Cursor layer (`ui/cursor_layer.c`)
Position in floats; mouse events add `dx·speed`; arrow keys (when no window has text focus and dock isn't focused… simpler: `Alt+arrows` always) move by 12 px/frame with acceleration while held; `Alt+Enter` = click at cursor. Cursor hidden until first mouse/arrow movement when `mouse_present=false`.

### 9.9 Console window (`ui/console.c`, `shell/commands.c`)
Window 720×440, monospace-ish look using Inter Regular 13 (v1 has no monospace font; acceptable). Content: last N lines of `klog_ring` + shell output (shared 200-line ring, 120 cols), input line with blinking caret (500 ms), prompt `gzowo> `. Keys: printable, Backspace, Enter, ↑/↓ history (16), Ctrl+L clear. Commands: `help`, `mem` (PMM/heap stats), `battery` (full struct + source), `time`, `uptime`, `cpu` (CPUID brand, features), `fb` (resolution/pitch/format), `acpi` (tables list, LAI status), `fps`, `clear`, `echo`, `sim battery <n>|ac on|off` (simulated only), `reboot`, `shutdown` (ACPI S5 via `lai_enter_sleep(5)` if LAI ok, else message), `panic` (test the panic screen), `ver`. The command table is a `struct { name, help, fn(argc, argv, out) }` array.

### 9.10 About window (`ui/about.c`)
480×320: wordmark (SemiBold 28), "Version 1.0 (build DATE)", CPU brand string, memory "512 MB (used 38 MB)", display "1280×800 @32bpp", uptime, battery source, "Fonts: Inter (OFL)", "Bootloader: Limine".

### 9.11 Settings window (`ui/settings.c`)
Minimal: toggle rows (drawn switches, click/Enter to toggle) for "Show FPS overlay", "Reduce motion" (durations ×0.35), "Simulated battery drain: slow/normal/fast", "Dark menubar".

### 9.12 Panic screen (`arch/panic.c`)
Works without heap/text engine: fills the framebuffer directly (row-sequential writes) with #1c1c1e, draws with font8x8 ×2: "Gzowo OS stopped." + message + register dump + stack trace; then `cli; hlt` forever. If the framebuffer isn't available yet, serial only. Also prints to serial first (in case the framebuffer path itself faults; recursion guard).

**M5 verified when (the full "what Jurek sees" list):** desktop with wallpaper, translucent blurred menubar with clock and animated battery, dock with 5 magnifying icons, bouncing launch, About and Terminal windows opening with scale+fade, draggable by mouse, closable with the red light / Esc / Alt+W, keyboard-only navigation works with the mouse forced absent, `reboot` restarts, F12 overlay shows ≥ 55 fps during a window drag at 1280×800 (HVF) and the static desktop consumes ~0 CPU (QEMU process idle in Activity Monitor).

## 10. kmain init sequence (final order)

```
serial_init → klog banner → limine checks → gfx_early_init(fb)  [panic screen possible from here]
gdt_init → idt_init → pic_init → acpi_tables_init(rsdp) → pmm_init → vmm_init+switch → heap_init
lapic_init(madt) → timer_calibrate → timer_start(1kHz) → sti → rtc_init
gfx_init (backbuffer, cursor, font8x8) → text_init (stb faces) → ui_init → scene = SPLASH (first frame drawn now)
[splash step 1] font warm-up      [step 2] ps2_init      [step 3] lai_init + battery_init      [step 4] wallpaper/blur caches
scene → LOCK → main loop
```
The splash progress bar is driven by real steps (targets 0.25/0.5/0.8/1.0 with tweened fill), minimum splash duration 1.4 s so it never flashes.

## 11. Milestones

| M | Scope | Verified when |
|---|-------|---------------|
| M0 | `brew install lld nasm xorriso qemu`; `tools/fetch-deps.sh`; Makefile, linker.ld, limine.conf, entry.asm, limine_req.c, minimal kmain that fills the framebuffer with a gradient; make-iso, run-qemu (UEFI+BIOS) | Gradient visible in QEMU via both UEFI and BIOS boot; `make` is incremental; `make clean && make` works from a fresh clone after `fetch-deps` |
| M1 | serial, printf, GDT/TSS, IDT/exceptions, PIC, PMM, VMM+PAT, heap, PIT/LAPIC/TSC timers, RTC, panic screen, `make test` with isa-debug-exit | §4 gate; `panic` shows the panic screen; `int3` test passes |
| M2 | i8042 keyboard+mouse, keymap, event queue, 1 kHz drain | §5 gate |
| M3 | gfx library, blit/present, text (stb+Inter), cursor sprite, test scene | §7 gate |
| M4 | anim, easing, springs, frame pacing, scene machine, wallpaper, splash, lock screen, FPS overlay | §8 gate |
| M5 | compositor, WM, windows (About, Terminal, Settings, Power dialog, Files stub), dock, menubar, battery widget with simulated battery, shell commands, keyboard navigation | §9 gate |
| M6 | ACPI tables → LAI → EC → real battery/AC; reboot chain; `acpi`/`battery`/`shutdown` commands | §6 gate |
| M7 | Real-hardware polish (checklist §12), USB script, 1080p perf pass (movntdq blit, blur caching audit), README for Jurek | Boots on the HP laptop from USB to the desktop with working keyboard; battery shows the real percentage; no tearing seen on the wallpaper during window drag |

Each milestone is committed to git (`git commit` at the end of each; branch `main`).

## 12. Real-hardware readiness checklist (M7, but write code this way from M0)

- Framebuffer: always use `pitch`; check masks; support 1920×1080 (and 2560×1440 for safety) — surfaces are allocated from the reported size, never constants. `UI_SCALE` 1.25 at 1080p on a 15" panel (the UI/UX agent may tune).
- WC via PAT on our own page tables (§4.7). Framebuffer writes sequential only. Never read the framebuffer.
- Interrupts: legacy PIC + LAPIC LINT0 ExtINT (virtual-wire); the 1 kHz i8042 polling drain makes keyboard/mouse work even if IRQ1/12 routing is broken. Contingency documented: `arch/ioapic.c` (MADT-driven, IRQ1/12 with ISO overrides) behind `#define GZOWO_USE_IOAPIC` if M7 testing shows the PIC path is silent.
- PS/2: touchpad may be I2C (then no aux device) — handled by the absence path; the internal keyboard on the HP Pavilion 15-ec is PS/2 via the EC — expected to work. FADT `IAPC_BOOT_ARCH` "no 8042" is logged but ignored.
- Firmware may leave the LAPIC timer/PIT in odd states: we reprogram both. TSC calibrated with PIT; log if LAPIC Hz looks absurd (<1 MHz or >5 GHz) and fall back to 1 kHz from PIT IRQ0 (unmask it) — implement that fallback (`timer_fallback_pit()`), it is cheap.
- Memory: laptop has ≥ 16 GB → memmap entries above 4 GiB; PMM bitmap sized from the highest usable address; HHDM built with 2 MiB pages covers all; ACPI tables may be above 4 GiB (covered).
- ACPI: `lai_create_namespace` on a real DSDT with many SSDTs: set heap growth unlimited; LAI warnings are logged, not fatal; a 3 s watchdog (tick-based) around LAI init: if exceeded, log and continue with the simulated battery (LAI has no cancellation; the watchdog only means "on the next return, abandon"). EC init is what makes `_BST` work on laptops — do not skip.
- NMI/SMI: leave LINT1 as NMI; ignore.
- Idle uses `hlt` — required for temperature/fan on the laptop.
- Panic screen on the framebuffer (no serial on the laptop). Additionally, every subsystem's init prints a short line to the framebuffer during the splash in a debug build (`GZOWO_VERBOSE_BOOT`) so a hang is attributable without serial.
- Secure Boot off (user). USB: GPT-less hybrid ISO image written raw is bootable by the HP firmware as a removable UEFI device (EFI/BOOT/BOOTX64.EFI). If the firmware refuses the ISO9660 hybrid, plan B in `write-usb.sh --fat`: `diskutil eraseDisk FAT32 GZOWO GPT /dev/diskN`, copy `EFI/BOOT/BOOTX64.EFI`, `boot/kernel.elf`, `boot/limine/limine.conf` (UEFI-only; no `bios-install` needed).
- QEMU vs hardware differences to keep in mind: QEMU has no battery/EC (simulated path), OVMF picks 1280×800 unless `resolution:` is set, HVF timing is close to native; TCG is 5–10× slower (do not judge fps under TCG).

## 13. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| LAI doesn't compile freestanding with clang | It is plain C99; compile with `-Wno-everything`; provide `memcpy/memset/memcmp/strlen`; if a missing libc symbol appears, add it to `lib/string.c`. Plan B: `-DGZOWO_NO_LAI` build with the simulated battery (§6.7). Plan C (later): uACPI. |
| SSE in freestanding code | Enabled deliberately (§3.1): CR0/CR4 set in entry.asm, fxsave/fxrstor in ISR stubs, 16-byte aligned stacks/heap; `-mno-avx` prevents non-baseline ISA. |
| clang emitting `memcpy` calls or vectorised aligned stores on unaligned data | `-fno-builtin`; provide the four mem functions; all surfaces/heap 16-byte aligned; row starts aligned (allocate stride rounded to 4 px). |
| PAT/WC mistakes → very slow or corrupt screen on the laptop | PAT layout copied from Limine's; verify with `rdmsr 0x277` log; 2 MiB PDE PAT bit is bit 12 (not 7). Fallback flag `GZOWO_FB_UC` to disable WC for debugging. |
| PIC IRQs silent on AMD laptop | 1 kHz i8042 polling drain (§5.4); IOAPIC contingency. |
| 1080p full-frame compositing too slow | Dirty rects + cached wallpaper/blur/shadow; idle frames skipped entirely; optional `movntdq` blit. Budget: full-frame present 8.3 MB ≈ 1.5 ms at 6 GB/s RAM (QEMU) or ≈ 3–4 ms WC on real HW; window drag typically dirties < 40 %. |
| Font rasterisation stalls on first use | Warm-up during splash; cache never evicts; sizes are a fixed list. |
| Space in the project path | Makefile uses only relative paths; scripts quote; `nasm -I.` relative incbin paths. |
| Limine base revision 6 unsupported by an older vendored binary | We vendor v12.8.0 which supports it; the kernel checks `LIMINE_BASE_REVISION_SUPPORTED` and halts with a serial message otherwise. |
| RTC wrong century / 12 h mode | Handled in `rtc.c`; FADT century register used when present. |
| Tearing | Accepted single-seam risk mitigated by fast top-to-bottom dirty presents (§7.2); document that true vsync requires a display driver (v2). |

## 14. Handoff notes for the UI/UX agent
Files you own: `ui/theme.h` (all colours/sizes/durations), `ui/wallpaper.c`, the `draw` functions in `ui/menubar.c`, `ui/dock.c` (icon drawing + magnification curve), `ui/battery_widget.c`, `ui/window.c` (chrome only), `ui/lock.c`, `ui/splash.c`, `gfx/cursor.c` (polygon). Available primitives: §7.3–7.8. Constraints: no new blur regions per frame without caching; keep total per-frame blur pixels ≤ 200 k at 1080p; keep font sizes within the fixed list or add to it (warm-up cost ~30 ms per size); durations ≤ 400 ms for anything on the input path.

---

### Critical Files for Implementation
- `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/v1/Makefile` (flags, LAI build, ISO/run targets — everything hinges on the toolchain decisions in §3)
- `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/v1/kernel/kmain.c` (init order and the frame-paced main loop, §10 and §8)
- `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/v1/kernel/mm/vmm.c` (own page tables + PAT/WC framebuffer mapping, §4.7 — the main real-hardware performance risk)
- `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/v1/kernel/ui/compositor.c` (layers, dirty-rect policy, blur/shadow caching, §9.3 and §7.2)
- `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/v1/kernel/acpi/laihost.c` + `power/battery_acpi.c` (LAI glue and battery evaluation, §6)

Note for the parent agent: save the plan section above (from "# Gzowo OS — v1 Implementation Plan" to the end of §14) as `/Users/jurek/Downloads/Claude/Projects/Gzowo OS/Niepotrzebne/PLAN.md`; this planning session was read-only and could not create it.