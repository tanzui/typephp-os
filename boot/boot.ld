OUTPUT_FORMAT("elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    . = 0x7c00;

    .text :
    {
        *(.text*)
    }

    .rodata :
    {
        *(.rodata*)
    }

    .data :
    {
        *(.data*)
    }

    /* BIOS 启动扇区的签名必须位于第 510、511 字节。 */
    . = 0x7dfe;
    .boot_signature :
    {
        SHORT(0xaa55)
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame)
    }
}

ASSERT(SIZEOF(.boot_signature) == 2, "启动签名大小错误")
ASSERT(. <= 0x7e00, "启动扇区超过 512 字节")
