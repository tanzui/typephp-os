// TypeOS 硬件抽象层：只负责 VGA 文本、PS/2 键盘和复位端口。
// shell、命令解析和演示文件系统全部位于 typephp/kernel.php。

using u8 = unsigned char;
using u16 = unsigned short;
using u32 = unsigned int;

namespace
{
constexpr u16 kVgaColumns = 80;
constexpr u16 kVgaRows = 25;
constexpr u16 kVgaControlPort = 0x3d4;
constexpr u16 kVgaDataPort = 0x3d5;
constexpr u16 kKeyboardDataPort = 0x60;
constexpr u16 kKeyboardStatusPort = 0x64;

volatile u16* const kVgaMemory = reinterpret_cast<volatile u16*>(0xb8000);

u8 g_terminalColor = 0x07;
u16 g_cursorRow = 0;
u16 g_cursorColumn = 0;
bool g_shiftLeft = false;
bool g_shiftRight = false;
bool g_extendedKey = false;

// 美国键盘布局的扫描码表。功能键和数字键盘暂时不参与 shell 输入。
const char kKeyboardMap[128] = {
    0,    0,    '1',  '2',  '3',  '4',  '5',  '6',
    '7',  '8',  '9',  '0',  '-',  '=',  '\b', '\t',
    'q',  'w',  'e',  'r',  't',  'y',  'u',  'i',
    'o',  'p',  '[',  ']',  '\n', 0,    'a',  's',
    'd',  'f',  'g',  'h',  'j',  'k',  'l',  ';',
    '\'', '`', 0,    '\\', 'z',  'x',  'c',  'v',
    'b',  'n',  'm',  ',',  '.',  '/', 0,    '*',
    0,    ' ', 0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,
};

/// <summary>
/// 从 x86 I/O 端口读取一个字节。
/// </summary>
/// <param name="port">要读取的端口号。</param>
/// <returns>端口返回的字节。</returns>
inline u8 port_in(u16 port)
{
    u8 value;
    __asm__ volatile("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

/// <summary>
/// 向 x86 I/O 端口写入一个字节。
/// </summary>
/// <param name="port">要写入的端口号。</param>
/// <param name="value">要写入的字节。</param>
inline void port_out(u16 port, u8 value)
{
    __asm__ volatile("outb %0, %1" : : "a"(value), "Nd"(port));
}

/// <summary>
/// 把软件维护的终端位置同步到 VGA CRT 控制器。
///
/// BIOS 输出使用自己的光标位置；TypeOS 直接写显存后必须主动更新 0x3d4/0x3d5，
/// 否则用户看到的光标会停在启动提示信息附近，而不是命令行末尾。
/// </summary>
void terminal_update_cursor()
{
    const u16 position = g_cursorRow * kVgaColumns + g_cursorColumn;

    // 显式设置光标形状并清除“隐藏光标”位，兼容不同虚拟机的 BIOS 初始状态。
    port_out(kVgaControlPort, 0x0a);
    port_out(kVgaDataPort, 0x0e);
    port_out(kVgaControlPort, 0x0b);
    port_out(kVgaDataPort, 0x0f);

    port_out(kVgaControlPort, 0x0f);
    port_out(kVgaDataPort, static_cast<u8>(position & 0xff));
    port_out(kVgaControlPort, 0x0e);
    port_out(kVgaDataPort, static_cast<u8>((position >> 8) & 0xff));
}

/// <summary>
/// 生成 VGA 文本模式单元。
/// </summary>
/// <param name="character">要显示的字符。</param>
/// <returns>包含字符和颜色的显存单元。</returns>
inline u16 make_vga_cell(char character)
{
    return static_cast<u16>(static_cast<u8>(character)) |
           (static_cast<u16>(g_terminalColor) << 8);
}

/// <summary>
/// 滚动一行 VGA 文本，避免输出超过屏幕高度后写出显存范围。
/// </summary>
void terminal_scroll()
{
    for (u16 row = 1; row < kVgaRows; ++row)
    {
        for (u16 column = 0; column < kVgaColumns; ++column)
        {
            kVgaMemory[(row - 1) * kVgaColumns + column] =
                kVgaMemory[row * kVgaColumns + column];
        }
    }

    for (u16 column = 0; column < kVgaColumns; ++column)
    {
        kVgaMemory[(kVgaRows - 1) * kVgaColumns + column] = make_vga_cell(' ');
    }
}

/// <summary>
/// 让硬件终端光标前进一行。
/// </summary>
void terminal_newline()
{
    g_cursorColumn = 0;
    ++g_cursorRow;
    if (g_cursorRow >= kVgaRows)
    {
        terminal_scroll();
        g_cursorRow = kVgaRows - 1;
    }
    terminal_update_cursor();
}

/// <summary>
/// 删除终端中最后一个已经回显的字符。
/// </summary>
void terminal_backspace()
{
    if (g_cursorColumn > 0)
    {
        --g_cursorColumn;
    }
    else if (g_cursorRow > 0)
    {
        --g_cursorRow;
        g_cursorColumn = kVgaColumns - 1;
    }
    else
    {
        return;
    }

    kVgaMemory[g_cursorRow * kVgaColumns + g_cursorColumn] = make_vga_cell(' ');
    terminal_update_cursor();
}

/// <summary>
/// 将字符写入 VGA 文本终端。
/// </summary>
/// <param name="character">要写入的 ASCII 字符。</param>
void terminal_putchar(char character)
{
    if (character == '\n')
    {
        terminal_newline();
        return;
    }
    if (character == '\r')
    {
        g_cursorColumn = 0;
        terminal_update_cursor();
        return;
    }
    if (character == '\b')
    {
        terminal_backspace();
        return;
    }
    if (character == '\t')
    {
        terminal_putchar(' ');
        terminal_putchar(' ');
        terminal_putchar(' ');
        terminal_putchar(' ');
        return;
    }

    kVgaMemory[g_cursorRow * kVgaColumns + g_cursorColumn] =
        make_vga_cell(character);
    ++g_cursorColumn;
    if (g_cursorColumn >= kVgaColumns)
    {
        terminal_newline();
        return;
    }
    terminal_update_cursor();
}

/// <summary>
/// 将 Shift 修饰的扫描码转换为 ASCII 字符。
/// </summary>
/// <param name="scanCode">键盘扫描码。</param>
/// <param name="character">未修饰字符。</param>
/// <returns>带 Shift 修饰后的字符。</returns>
char apply_shift(u8 scanCode, char character)
{
    if (character >= 'a' && character <= 'z')
    {
        return static_cast<char>(character - 'a' + 'A');
    }

    switch (scanCode)
    {
        case 0x02: return '!';
        case 0x03: return '@';
        case 0x04: return '#';
        case 0x05: return '$';
        case 0x06: return '%';
        case 0x07: return '^';
        case 0x08: return '&';
        case 0x09: return '*';
        case 0x0a: return '(';
        case 0x0b: return ')';
        case 0x0c: return '_';
        case 0x0d: return '+';
        case 0x1a: return '{';
        case 0x1b: return '}';
        case 0x27: return ':';
        case 0x28: return '"';
        case 0x29: return '~';
        case 0x2b: return '|';
        case 0x33: return '<';
        case 0x34: return '>';
        case 0x35: return '?';
        default: return character;
    }
}

/// <summary>
/// 从键盘控制器读取一个可用的 ASCII 字符。
/// </summary>
/// <returns>普通字符、回车或退格；功能键会被忽略。</returns>
char keyboard_read_char()
{
    while (true)
    {
        if ((port_in(kKeyboardStatusPort) & 0x01) == 0)
        {
            // 当前没有中断驱动，使用 pause 降低忙等对虚拟 CPU 的压力。
            __asm__ volatile("pause");
            continue;
        }

        const u8 scanCode = port_in(kKeyboardDataPort);
        if (scanCode == 0xe0)
        {
            g_extendedKey = true;
            continue;
        }

        if ((scanCode & 0x80) != 0)
        {
            const u8 releasedCode = static_cast<u8>(scanCode & 0x7f);
            if (releasedCode == 0x2a)
            {
                g_shiftLeft = false;
            }
            else if (releasedCode == 0x36)
            {
                g_shiftRight = false;
            }
            g_extendedKey = false;
            continue;
        }

        if (g_extendedKey)
        {
            // 第一版不处理方向键，但要消费扩展扫描码。
            g_extendedKey = false;
            continue;
        }

        if (scanCode == 0x2a)
        {
            g_shiftLeft = true;
            continue;
        }
        if (scanCode == 0x36)
        {
            g_shiftRight = true;
            continue;
        }
        if (scanCode >= sizeof(kKeyboardMap))
        {
            continue;
        }

        const char baseCharacter = kKeyboardMap[scanCode];
        if (baseCharacter == '\0')
        {
            continue;
        }

        return (g_shiftLeft || g_shiftRight)
                   ? apply_shift(scanCode, baseCharacter)
                   : baseCharacter;
    }
}

/// <summary>
/// 初始化 VGA 终端并清空整个屏幕。
/// </summary>
void terminal_clear()
{
    for (u16 row = 0; row < kVgaRows; ++row)
    {
        for (u16 column = 0; column < kVgaColumns; ++column)
        {
            kVgaMemory[row * kVgaColumns + column] = make_vga_cell(' ');
        }
    }
    g_cursorRow = 0;
    g_cursorColumn = 0;
    terminal_update_cursor();
}
} // namespace

extern "C" void php_hal_putc(long long value)
{
    terminal_putchar(static_cast<char>(value));
}

extern "C" long long php_hal_getc()
{
    return static_cast<long long>(static_cast<unsigned char>(keyboard_read_char()));
}

extern "C" void php_hal_clear()
{
    terminal_clear();
}

extern "C" void php_hal_reboot()
{
    // 8042 控制器的 0xfe 命令是传统 PC 和大多数虚拟机都支持的复位方式。
    for (u32 attempt = 0; attempt < 100000; ++attempt)
    {
        if ((port_in(kKeyboardStatusPort) & 0x02) == 0)
        {
            break;
        }
    }
    port_out(kKeyboardStatusPort, 0xfe);
    while (true)
    {
        __asm__ volatile("cli; hlt");
    }
}

extern "C" void php_hal_halt()
{
    while (true)
    {
        __asm__ volatile("cli; hlt");
    }
}
