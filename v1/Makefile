# Gzowo OS build. Run from v1/. All paths relative (project dir contains a space).

CC      ?= /usr/local/opt/llvm/bin/clang
LD      := /usr/local/bin/ld.lld
NASM    ?= nasm

BUILD   := build
OBJDIR  := $(BUILD)/obj

CFLAGS  := --target=x86_64-unknown-elf -std=gnu11 -O2 -g -pipe \
           -ffreestanding -nostdlibinc -fno-stack-protector -fno-stack-check -fno-lto \
           -fno-pic -fno-pie -fno-builtin -fno-omit-frame-pointer \
           -ffunction-sections -fdata-sections \
           -mno-red-zone -mcmodel=kernel -march=x86-64 -mno-avx -mno-avx2 -mno-mmx -mno-80387 \
           -Wall -Wextra -Wno-unused-parameter -MMD -MP \
           -Ikernel/include -Ithird_party/limine -Ithird_party/lai/include -Ithird_party/stb

LAI_CFLAGS := $(filter-out -Wall -Wextra,$(CFLAGS)) -w
NASMFLAGS  := -f elf64 -g -F dwarf -Wall
LDFLAGS    := -nostdlib -static -z max-page-size=0x1000 -z noexecstack --gc-sections -T linker.ld -m elf_x86_64

CSRC   := $(shell find kernel -name '*.c' | sort)
ASMSRC := $(shell find kernel -name '*.asm' | sort)
LAISRC := $(wildcard third_party/lai/core/*.c) $(wildcard third_party/lai/helpers/*.c) $(wildcard third_party/lai/drivers/*.c)

COBJ   := $(CSRC:%.c=$(OBJDIR)/%.o)
AOBJ   := $(ASMSRC:%.asm=$(OBJDIR)/%.o)
LAIOBJ := $(LAISRC:%.c=$(OBJDIR)/%.o)
OBJ    := $(COBJ) $(AOBJ) $(LAIOBJ)
DEPS   := $(OBJ:.o=.d)

KERNEL := $(BUILD)/kernel.elf
ISO    := $(BUILD)/gzowo.iso

.PHONY: all iso run run-bios run-debug clean
all: $(KERNEL)
iso: $(ISO)
run: $(ISO); @./tools/run-qemu.sh
run-bios: $(ISO); @./tools/run-qemu.sh --bios
run-debug: $(ISO); @./tools/run-qemu.sh --debug

$(OBJDIR)/third_party/%.o: third_party/%.c
	@mkdir -p $(dir $@)
	$(CC) $(LAI_CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) $< -o $@

$(KERNEL): $(OBJ) linker.ld
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) $(OBJ) -o $@
	@echo "  built $@"

$(ISO): $(KERNEL) limine.conf tools/make-iso.sh
	@./tools/make-iso.sh

clean:
	rm -rf $(BUILD)

-include $(DEPS)
