#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

struct boot_info {
    uint32_t *fb;          /* HHDM virtual pointer to the framebuffer */
    uint64_t  fb_width, fb_height;
    uint64_t  fb_pitch;    /* bytes per scanline */
    uint32_t  fb_pixels_per_row; /* pitch / 4 */
    uint16_t  fb_bpp;
    uint64_t  hhdm;
    uintptr_t rsdp_phys;
    uint64_t  kernel_phys_base, kernel_virt_base;
    void     *memmap;      /* struct limine_memmap_response * */
};

extern struct boot_info boot;
bool boot_init(void);
static inline uintptr_t to_phys(uintptr_t a) { return a >= boot.hhdm ? a - boot.hhdm : a; }
static inline void *to_virt(uintptr_t p) { return (void *)(p + boot.hhdm); }
