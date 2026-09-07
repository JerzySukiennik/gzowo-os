; Gzowo OS kernel entry. Limine hands us long mode, paging on, IF=0.
bits 64
section .bss
align 16
stack_bottom: resb 65536
stack_top:

section .text
global _start
extern kmain
_start:
    cli
    lea rsp, [rel stack_top]
    and rsp, -16
    xor rbp, rbp

    ; Enable SSE (Limine base rev >= 5 does not guarantee it).
    mov rax, cr0
    and ax, 0xFFFB          ; CR0.EM = 0
    or  ax, 0x2             ; CR0.MP = 1
    mov cr0, rax
    mov rax, cr4
    or  ax, 3 << 9          ; CR4.OSFXSR | CR4.OSXMMEXCPT
    mov cr4, rax

    call kmain
.hang:
    cli
    hlt
    jmp .hang
