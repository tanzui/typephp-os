.intel_syntax noprefix
.code16

.section .text
.global _start

.equ KERNEL_LOAD_SEGMENT, 0x1000
.equ KERNEL_SECTORS, 128

// BIOS 将启动盘编号放在 DL 中，先保存下来供后续读盘使用。
_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    cld

    mov byte ptr [boot_drive], dl
    mov si, offset loading_message
    call print_string

    // 把内核从启动盘第 2 个扇区开始逐扇区读到物理地址 0x10000。
    // 每次只读一个扇区，避免跨磁道读取在不同 BIOS 中行为不一致。
    mov ax, KERNEL_LOAD_SEGMENT
    mov es, ax
    xor bx, bx
    mov byte ptr [disk_sector], 2
    mov byte ptr [disk_head], 0
    mov byte ptr [disk_track], 0
    mov byte ptr [sectors_left], KERNEL_SECTORS

read_kernel:
    cmp byte ptr [sectors_left], 0
    je kernel_loaded

    mov ah, 0x02
    mov al, 1
    mov ch, byte ptr [disk_track]
    mov cl, byte ptr [disk_sector]
    mov dh, byte ptr [disk_head]
    mov dl, byte ptr [boot_drive]
    int 0x13
    jc disk_error

    add bx, 512
    inc byte ptr [disk_sector]
    cmp byte ptr [disk_sector], 19
    jb read_next_sector

    // 1.44MB 软盘每条磁道有 18 个扇区，读完一面后切换磁头。
    mov byte ptr [disk_sector], 1
    inc byte ptr [disk_head]
    cmp byte ptr [disk_head], 2
    jb read_next_sector

    mov byte ptr [disk_head], 0
    inc byte ptr [disk_track]

read_next_sector:
    dec byte ptr [sectors_left]
    jmp read_kernel

kernel_loaded:
    call enable_a20

    // 切换到 32 位平坦内存模型，先进入下面的保护模式初始化代码。
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    // LLVM 汇编器对 16 位远跳转的 Intel 语法支持有限，这里直接写出机器码。
    .byte 0xea
    .word protected_mode_entry
    .word 0x08

.code32
protected_mode_entry:
    // 实模式中的段寄存器值不能直接用于保护模式，先装入平坦数据段选择子。
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    // 内核链接地址是 0x10000，使用绝对跳转避免依赖当前指令位置。
    mov eax, 0x10000
    jmp eax

.code16

disk_error:
    mov si, offset disk_error_message
    call print_string

halt_real_mode:
    cli
    hlt
    jmp halt_real_mode

// 使用 BIOS 显示服务输出以零结尾的 ASCII 字符串。
print_string:
    lodsb
    test al, al
    jz print_string_done
    mov ah, 0x0e
    mov bx, 0x0007
    int 0x10
    jmp print_string

print_string_done:
    ret

// 打开 A20 地址线，使保护模式代码可以正常访问 1MB 以上地址。
enable_a20:
wait_input_empty:
    in al, 0x64
    test al, 0x02
    jnz wait_input_empty
    mov al, 0xad
    out 0x64, al

wait_input_empty_again:
    in al, 0x64
    test al, 0x02
    jnz wait_input_empty_again
    mov al, 0xd1
    out 0x64, al

wait_input_empty_final:
    in al, 0x64
    test al, 0x02
    jnz wait_input_empty_final
    mov al, 0xdf
    out 0x60, al

    // 设置 A20 后重新启用键盘接口；否则后续 PS/2 控制器不会产生输入数据。
wait_input_empty_enable_keyboard:
    in al, 0x64
    test al, 0x02
    jnz wait_input_empty_enable_keyboard
    mov al, 0xae
    out 0x64, al
    ret

.align 8
gdt_start:
    // 空描述符
    .quad 0
    // 代码段：基址 0，4GB 限长，可执行、可读，粒度为 4KB
    .word 0xffff
    .word 0
    .byte 0
    .byte 0x9a
    .byte 0xcf
    .byte 0
    // 数据段：基址 0，4GB 限长，可读写，粒度为 4KB
    .word 0xffff
    .word 0
    .byte 0
    .byte 0x92
    .byte 0xcf
    .byte 0
gdt_end:

gdt_descriptor:
    .word gdt_end - gdt_start - 1
    .long gdt_start

.section .rodata
loading_message:
    .asciz "Loading TypeOS...\r\n"
disk_error_message:
    .asciz "Disk read error.\r\n"

.section .data
boot_drive:
    .byte 0
disk_sector:
    .byte 0
disk_head:
    .byte 0
disk_track:
    .byte 0
sectors_left:
    .byte 0
