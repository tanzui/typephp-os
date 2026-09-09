.intel_syntax noprefix
.code32

.section .text.entry,"ax"
.global _start
.extern typephp_kernel_main
.extern __bss_start
.extern __bss_end

_start:
    cli
    mov esp, 0x90000
    xor ebp, ebp
    cld

    // 裸机没有 C/C++ 运行时负责清零 BSS，这里在调用 C++ 代码前手动完成。
    mov edi, offset __bss_start
    mov ecx, offset __bss_end
    sub ecx, edi
    xor eax, eax
    rep stosb

    call typephp_kernel_main

kernel_halt:
    cli
    hlt
    jmp kernel_halt
