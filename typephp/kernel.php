<?php

declare(strict_types=1);

// TypeOS 的策略层完全使用 TypePHP 编写。
// 这里刻意只使用 int、bool、循环和函数调用，便于生成代码脱离 PHPX 运行时后仍能裸机链接。

/**
 * 返回退格键的 ASCII 值。
 *
 * TypePHP 的 const 会生成 PHPX 动态变量，裸机代码不能依赖它，因此固定值使用
 * 返回 int 的小函数表达。编译后它们仍然是普通的静态整数函数。
 */
function key_backspace(): int
{
    return 8;
}

/**
 * 返回回车键的 ASCII 值。
 */
function key_enter(): int
{
    return 10;
}

/**
 * 返回命令读取状态值。
 */
function mode_command(): int
{
    return 0;
}

/**
 * 返回 echo 命令读取状态值。
 */
function mode_echo(): int
{
    return 1;
}

/**
 * 返回 ls 命令读取状态值。
 */
function mode_ls(): int
{
    return 2;
}

/**
 * 返回 cat 命令读取状态值。
 */
function mode_cat(): int
{
    return 3;
}

/**
 * 返回未知命令读取状态值。
 */
function mode_unknown(): int
{
    return 4;
}

/**
 * 返回固定命令或路径的加权值。
 */
function hash_help(): int
{
    return 1078;
}

/**
 * 返回 clear 命令的加权值。
 */
function hash_clear(): int
{
    return 1576;
}

/**
 * 返回 echo 命令的加权值。
 */
function hash_echo(): int
{
    return 1055;
}

/**
 * 返回 ls 命令的加权值。
 */
function hash_ls(): int
{
    return 338;
}

/**
 * 返回 cat 命令的加权值。
 */
function hash_cat(): int
{
    return 641;
}

/**
 * 返回 uname 命令的加权值。
 */
function hash_uname(): int
{
    return 1569;
}

/**
 * 返回 about 命令的加权值。
 */
function hash_about(): int
{
    return 1674;
}

/**
 * 返回 pwd 命令的加权值。
 */
function hash_pwd(): int
{
    return 650;
}

/**
 * 返回 reboot 命令的加权值。
 */
function hash_reboot(): int
{
    return 2305;
}

/**
 * 返回 halt 命令的加权值。
 */
function hash_halt(): int
{
    return 1086;
}

/**
 * 返回 hello 参数的加权值。
 */
function hash_hello(): int
{
    return 1617;
}

/**
 * 返回 typephp 参数的加权值。
 */
function hash_typephp(): int
{
    return 3066;
}

/**
 * 返回根路径的加权值。
 */
function hash_root(): int
{
    return 47;
}

/**
 * 返回 /bin 路径的加权值。
 */
function hash_bin(): int
{
    return 998;
}

/**
 * 返回 /etc 路径的加权值。
 */
function hash_etc(): int
{
    return 993;
}

/**
 * 返回 /etc/motd 路径的加权值。
 */
function hash_motd(): int
{
    return 4487;
}

/**
 * 返回 /etc/os-release 路径的加权值。
 */
function hash_os_release(): int
{
    return 11881;
}

/**
 * 输出一个字符。硬件层只提供单字符接口，所有文本组合都留在 TypePHP 层。
 */
function put_char(int $value): void
{
    hal_putc($value);
}

/**
 * 输出换行。
 */
function put_newline(): void
{
    hal_putc(key_enter());
}

/**
 * 输出两个 ASCII 字符，减少内核文本常量在 TypePHP 中的重复代码。
 */
function put_two(int $first, int $second): void
{
    put_char($first);
    put_char($second);
}

/**
 * 输出三个 ASCII 字符。
 */
function put_three(int $first, int $second, int $third): void
{
    put_char($first);
    put_char($second);
    put_char($third);
}

/**
 * 输出四个 ASCII 字符。
 */
function put_four(int $first, int $second, int $third, int $fourth): void
{
    put_char($first);
    put_char($second);
    put_char($third);
    put_char($fourth);
}

/**
 * 显示启动信息。文本使用 ASCII 数字编码，避免裸 VGA 文本模式的编码差异。
 */
function show_banner(): void
{
    put_four(84, 121, 112, 101);
    put_four(79, 83, 32, 48);
    put_four(46, 49, 46, 48);
    put_newline();

    put_four(84, 121, 112, 101);
    put_four(80, 72, 80, 32);
    put_four(107, 101, 114, 110);
    put_four(101, 108, 32, 109);
    put_three(111, 100, 101);
    put_newline();

    put_four(84, 121, 112, 101);
    put_four(32, 39, 104, 101);
    put_four(108, 112, 39, 32);
    put_four(102, 111, 114, 32);
    put_four(99, 111, 109, 109);
    put_four(97, 110, 100, 115);
    put_char(46);
    put_newline();
    put_newline();
}

/**
 * 显示 shell 提示符。
 */
function show_prompt(): void
{
    put_four(116, 121, 112, 101);
    put_four(111, 115, 58, 47);
    put_two(35, 32);
}

/**
 * 显示第一版支持的命令。
 */
function show_help(): void
{
    put_four(104, 101, 108, 112);
    put_four(32, 45, 32, 108);
    put_four(105, 115, 116, 32);
    put_four(99, 111, 109, 109);
    put_four(97, 110, 100, 115);
    put_newline();

    put_four(99, 108, 101, 97);
    put_four(114, 32, 45, 32);
    put_four(99, 108, 101, 97);
    put_four(114, 32, 115, 99);
    put_four(114, 101, 101, 110);
    put_newline();

    put_four(101, 99, 104, 111);
    put_four(32, 45, 32, 112);
    put_four(114, 105, 110, 116);
    put_four(32, 116, 101, 120);
    put_char(116);
    put_newline();

    put_two(108, 115);
    put_four(32, 45, 32, 108);
    put_four(105, 115, 116, 32);
    put_four(118, 105, 114, 116);
    put_four(117, 97, 108, 32);
    put_four(100, 105, 114, 115);
    put_newline();

    put_three(99, 97, 116);
    put_four(32, 45, 32, 114);
    put_four(101, 97, 100, 32);
    put_four(118, 105, 114, 116);
    put_four(117, 97, 108, 32);
    put_four(102, 105, 108, 101);
    put_char(115);
    put_newline();

    put_four(117, 110, 97, 109);
    put_two(101, 32);
    put_four(45, 32, 107, 101);
    put_four(114, 110, 101, 108);
    put_four(32, 110, 97, 109);
    put_char(101);
    put_newline();

    put_four(97, 98, 111, 117);
    put_four(116, 32, 45, 32);
    put_four(112, 114, 111, 106);
    put_four(101, 99, 116, 32);
    put_four(105, 110, 102, 111);
    put_newline();

    put_three(112, 119, 100);
    put_four(32, 45, 32, 99);
    put_four(117, 114, 114, 101);
    put_four(110, 116, 32, 100);
    put_four(105, 114, 101, 99);
    put_four(116, 111, 114, 121);
    put_newline();

    put_four(114, 101, 98, 111);
    put_four(111, 116, 32, 45);
    put_four(32, 114, 101, 115);
    put_four(116, 97, 114, 116);
    put_two(32, 86);
    put_char(77);
    put_newline();

    put_four(104, 97, 108, 116);
    put_four(32, 45, 32, 115);
    put_four(116, 111, 112, 32);
    put_four(67, 80, 85, 32);
    put_newline();
}

/**
 * 显示根目录的固定内容。
 */
function show_root_directory(): void
{
    put_four(98, 105, 110, 32);
    put_four(32, 100, 101, 118);
    put_four(32, 32, 101, 116);
    put_four(99, 32, 32, 104);
    put_four(111, 109, 101, 32);
    put_four(32, 116, 109, 112);
    put_newline();
}

/**
 * 显示 /bin 目录的固定内容。
 */
function show_bin_directory(): void
{
    put_four(101, 99, 104, 111);
    put_four(32, 104, 101, 108);
    put_two(112, 32);
    put_four(108, 115, 32, 117);
    put_four(110, 97, 109, 101);
    put_newline();
}

/**
 * 显示 /etc 目录的固定内容。
 */
function show_etc_directory(): void
{
    put_four(109, 111, 116, 100);
    put_four(32, 111, 115, 45);
    put_four(114, 101, 108, 101);
    put_three(97, 115, 101);
    put_newline();
}

/**
 * 显示内存文件 /etc/motd。
 */
function show_motd(): void
{
    put_four(87, 101, 108, 99);
    put_four(111, 109, 101, 32);
    put_four(116, 111, 32, 84);
    put_four(121, 112, 101, 79);
    put_two(83, 46);
    put_newline();
}

/**
 * 显示内存文件 /etc/os-release。
 */
function show_os_release(): void
{
    put_four(78, 65, 77, 69);
    put_four(61, 84, 121, 112);
    put_three(101, 79, 83);
    put_newline();

    put_four(86, 69, 82, 83);
    put_four(73, 79, 78, 61);
    put_four(48, 46, 49, 46);
    put_char(48);
    put_newline();

    put_four(73, 68, 61, 116);
    put_four(121, 112, 101, 111);
    put_char(115);
    put_newline();
}

/**
 * 显示路径不存在的提示。
 */
function show_missing_path(): void
{
    put_four(78, 111, 32, 115);
    put_four(117, 99, 104, 32);
    put_four(102, 105, 108, 101);
    put_four(32, 111, 114, 32);
    put_four(100, 105, 114, 101);
    put_four(99, 116, 111, 114);
    put_two(121, 46);
    put_newline();
}

/**
 * 显示 echo 命令的两个固定示例结果。
 */
function show_echo_result(int $argumentHash, int $argumentLength): void
{
    if ($argumentLength == 0)
    {
        put_newline();
        return;
    }

    if ($argumentHash == hash_hello() && $argumentLength == 5)
    {
        put_four(104, 101, 108, 108);
        put_char(111);
        put_newline();
        return;
    }

    if ($argumentHash == hash_typephp() && $argumentLength == 7)
    {
        put_four(84, 121, 112, 101);
        put_three(80, 72, 80);
        put_newline();
        return;
    }

    put_four(101, 99, 104, 111);
    put_four(32, 111, 110, 108);
    put_four(121, 32, 115, 117);
    put_four(112, 112, 111, 114);
    put_four(116, 115, 32, 104);
    put_four(101, 108, 108, 111);
    put_four(32, 111, 114, 32);
    put_four(116, 121, 112, 101);
    put_four(112, 104, 112, 32);
    put_four(97, 114, 101, 32);
    put_four(115, 117, 112, 112);
    put_three(111, 114, 116);
    put_newline();
}

/**
 * 计算一行命令或参数的简单加权值。
 *
 * 第一版只允许固定 ASCII 命令，因此使用长度和位置加权和即可避免引入字符串运行时。
 */
function add_to_hash(int $hash, int $value, int $position): int
{
    return $hash + $value * $position;
}

/**
 * 读取一行命令，并把命令识别、参数识别交给 TypePHP 代码处理。
 *
 * 硬件层以阻塞方式返回一个字符；这样循环、状态和命令分派全部由 TypePHP 生成。
 */
function read_line_and_execute(): void
{
    $mode = mode_command();
    $commandHash = 0;
    $commandLength = 0;
    $argumentHash = 0;
    $argumentLength = 0;

    while (true)
    {
        $key = hal_getc();

        if ($key == key_enter())
        {
            put_newline();
            execute_command($commandHash, $commandLength, $mode, $argumentHash, $argumentLength);
            return;
        }

        if ($key == key_backspace())
        {
            // 退格时清除当前显示字符并重新开始识别，避免维护 PHP 字符串缓冲区。
            put_char(key_backspace());
            $mode = mode_command();
            $commandHash = 0;
            $commandLength = 0;
            $argumentHash = 0;
            $argumentLength = 0;
            continue;
        }

        if ($key < 32 || $key > 126)
        {
            continue;
        }

        put_char($key);
        if ($mode == mode_command())
        {
            if ($key == 32)
            {
                if ($commandHash == hash_echo() && $commandLength == 4)
                {
                    $mode = mode_echo();
                }
                else if ($commandHash == hash_ls() && $commandLength == 2)
                {
                    $mode = mode_ls();
                }
                else if ($commandHash == hash_cat() && $commandLength == 3)
                {
                    $mode = mode_cat();
                }
                else
                {
                    $mode = mode_unknown();
                }
                continue;
            }

            $commandLength = $commandLength + 1;
            $commandHash = add_to_hash($commandHash, $key, $commandLength);
            continue;
        }

        if ($key != 32)
        {
            $argumentLength = $argumentLength + 1;
            $argumentHash = add_to_hash($argumentHash, $key, $argumentLength);
        }
    }
}

/**
 * 执行一条已经由 TypePHP 读取并分类的 shell 命令。
 */
function execute_command(
    int $commandHash,
    int $commandLength,
    int $mode,
    int $argumentHash,
    int $argumentLength
): void
{
    if ($mode == mode_echo())
    {
        show_echo_result($argumentHash, $argumentLength);
        return;
    }

    if ($mode == mode_ls())
    {
        if ($argumentLength == 0 || ($argumentHash == hash_root() && $argumentLength == 1))
        {
            show_root_directory();
        }
        else if ($argumentHash == hash_bin() && $argumentLength == 4)
        {
            show_bin_directory();
        }
        else if ($argumentHash == hash_etc() && $argumentLength == 4)
        {
            show_etc_directory();
        }
        else
        {
            show_missing_path();
        }
        return;
    }

    if ($mode == mode_cat())
    {
        if ($argumentHash == hash_motd() && $argumentLength == 9)
        {
            show_motd();
        }
        else if ($argumentHash == hash_os_release() && $argumentLength == 15)
        {
            show_os_release();
        }
        else
        {
            show_missing_path();
        }
        return;
    }

    if ($commandHash == hash_help() && $commandLength == 4)
    {
        show_help();
    }
    else if ($commandHash == hash_clear() && $commandLength == 5)
    {
        hal_clear();
    }
    else if ($commandHash == hash_echo() && $commandLength == 4)
    {
        show_echo_result(0, 0);
    }
    else if ($commandHash == hash_ls() && $commandLength == 2)
    {
        show_root_directory();
    }
    else if ($commandHash == hash_cat() && $commandLength == 3)
    {
        show_missing_path();
    }
    else if ($commandHash == hash_uname() && $commandLength == 5)
    {
        put_four(84, 121, 112, 101);
        put_four(79, 83, 32, 105);
        put_four(51, 56, 54, 32);
        put_four(98, 97, 114, 101);
        put_four(109, 101, 116, 97);
        put_two(108, 46);
        put_newline();
    }
    else if ($commandHash == hash_about() && $commandLength == 5)
    {
        put_four(84, 121, 112, 101);
        put_four(79, 83, 32, 105);
        put_four(115, 32, 84, 121);
        put_four(112, 101, 80, 72);
        put_four(80, 45, 102, 105);
        put_four(114, 115, 116, 46);
        put_newline();
    }
    else if ($commandHash == hash_pwd() && $commandLength == 3)
    {
        put_char(47);
        put_newline();
    }
    else if ($commandHash == hash_reboot() && $commandLength == 6)
    {
        put_four(82, 101, 98, 111);
        put_four(111, 116, 105, 110);
        put_four(103, 46, 46, 46);
        put_newline();
        hal_reboot();
    }
    else if ($commandHash == hash_halt() && $commandLength == 4)
    {
        put_four(83, 121, 115, 116);
        put_four(101, 109, 32, 104);
        put_four(97, 108, 116, 101);
        put_char(100);
        put_newline();
        hal_halt();
    }
    else
    {
        put_four(116, 121, 112, 101);
        put_four(111, 115, 58, 32);
        put_four(99, 111, 109, 109);
        put_four(97, 110, 100, 32);
        put_four(110, 111, 116, 32);
        put_four(102, 111, 117, 110);
        put_two(100, 46);
        put_newline();
    }
}

/**
 * TypeOS 的 TypePHP 内核入口。
 */
function main(): void
{
    hal_clear();
    show_banner();

    while (true)
    {
        show_prompt();
        read_line_and_execute();
    }
}
