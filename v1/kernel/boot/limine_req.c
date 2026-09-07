#include <limine.h>
#include "boot.h"

__attribute__((used, section(".limine_requests_start")))
static volatile uint64_t start_marker[4] = LIMINE_REQUESTS_START_MARKER;

__attribute__((used, section(".limine_requests")))
static volatile uint64_t base_rev[3] = LIMINE_BASE_REVISION(3);

__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request fb_req = {
    .id = LIMINE_FRAMEBUFFER_REQUEST_ID, .revision = 0 };

__attribute__((used, section(".limine_requests")))
static volatile struct limine_memmap_request memmap_req = {
    .id = LIMINE_MEMMAP_REQUEST_ID, .revision = 0 };

__attribute__((used, section(".limine_requests")))
static volatile struct limine_hhdm_request hhdm_req = {
    .id = LIMINE_HHDM_REQUEST_ID, .revision = 0 };

__attribute__((used, section(".limine_requests")))
static volatile struct limine_rsdp_request rsdp_req = {
    .id = LIMINE_RSDP_REQUEST_ID, .revision = 0 };

__attribute__((used, section(".limine_requests")))
static volatile struct limine_executable_address_request exec_req = {
    .id = LIMINE_EXECUTABLE_ADDRESS_REQUEST_ID, .revision = 0 };

__attribute__((used, section(".limine_requests_end")))
static volatile uint64_t end_marker[2] = LIMINE_REQUESTS_END_MARKER;

struct boot_info boot;

bool boot_init(void) {
    if (!LIMINE_BASE_REVISION_SUPPORTED(base_rev)) return false;
    if (!hhdm_req.response) return false;
    boot.hhdm = hhdm_req.response->offset;

    if (!fb_req.response || fb_req.response->framebuffer_count < 1) return false;
    struct limine_framebuffer *f = fb_req.response->framebuffers[0];
    boot.fb = (uint32_t *)f->address;
    boot.fb_width = f->width;
    boot.fb_height = f->height;
    boot.fb_pitch = f->pitch;
    boot.fb_pixels_per_row = (uint32_t)(f->pitch / 4);
    boot.fb_bpp = f->bpp;
    if (f->bpp != 32) return false;

    boot.memmap = memmap_req.response;
    boot.rsdp_phys = rsdp_req.response ? to_phys((uintptr_t)rsdp_req.response->address) : 0;
    if (exec_req.response) {
        boot.kernel_phys_base = exec_req.response->physical_base;
        boot.kernel_virt_base = exec_req.response->virtual_base;
    }
    return true;
}
