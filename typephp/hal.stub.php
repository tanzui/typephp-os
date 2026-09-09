<?php

/**
 * TypeOS 裸机硬件接口声明。
 *
 * 这些函数没有 PHP 实现，最终由 kernel/hal.cpp 提供；TypePHP 编译器
 * 会把调用转换成 php_hal_* 的原生 C++ 函数调用。
 */
function hal_putc(int $value): void {}
function hal_getc(): int {}
function hal_clear(): void {}
function hal_reboot(): void {}
function hal_halt(): void {}
