#include "boot.h"

static inline void outb(uint16_t p, uint8_t v) { __asm__ volatile("outb %0,%1"::"a"(v),"Nd"(p)); }
static inline uint8_t inb(uint16_t p) { uint8_t v; __asm__ volatile("inb %1,%0":"=a"(v):"Nd"(p)); return v; }

static void serial_init(void) {
    outb(0x3F8+1,0x00); outb(0x3F8+3,0x80); outb(0x3F8+0,0x03); outb(0x3F8+1,0x00);
    outb(0x3F8+3,0x03); outb(0x3F8+2,0xC7); outb(0x3F8+4,0x0B);
}
static void sputc(char c) { while (!(inb(0x3F8+5) & 0x20)) { } outb(0x3F8, (uint8_t)c); }
static void sputs(const char *s) { while (*s) { if (*s=='\n') sputc('\r'); sputc(*s++); } }
static void sputu(uint64_t v) { char b[24]; int i=0; if(!v){sputc('0');return;} while(v){b[i++]='0'+(char)(v%10);v/=10;} while(i)sputc(b[--i]); }

static void hcf(void) { for (;;) __asm__ volatile("cli; hlt"); }

void kmain(void) {
    serial_init();
    sputs("\n[boot] Gzowo OS kernel entry\n");

    if (!boot_init()) { sputs("[fail] boot_init\n"); hcf(); }

    sputs("[ok] framebuffer "); sputu(boot.fb_width); sputs("x"); sputu(boot.fb_height);
    sputs(" pitch "); sputu(boot.fb_pitch); sputs(" bpp "); sputu(boot.fb_bpp); sputs("\n");
    sputs("[ok] hhdm 0x"); { uint64_t h=boot.hhdm; char hex[17]; for(int i=15;i>=0;i--){hex[15-i]="0123456789abcdef"[(h>>(i*4))&0xF];} hex[16]=0; sputs(hex);} sputs("\n");

    /* M0 proof of life: vertical gradient wash. */
    for (uint64_t y = 0; y < boot.fb_height; y++) {
        uint32_t *row = boot.fb + y * boot.fb_pixels_per_row;
        uint32_t t = (uint32_t)(y * 255 / (boot.fb_height ? boot.fb_height : 1));
        uint32_t px = ((10 + t/8) << 16) | ((12 + t/6) << 8) | (18 + t/4);
        for (uint64_t x = 0; x < boot.fb_width; x++) row[x] = px;
    }
    sputs("[ok] framebuffer painted\n");
    hcf();
}
