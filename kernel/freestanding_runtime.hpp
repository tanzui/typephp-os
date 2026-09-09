#pragma once

// TypePHP 纯标量函数在生成代码中只需要这两个轻量转换函数。
// PHPX/Zend 包装层不会进入裸机镜像，因此这里不引入任何标准库或运行库。
namespace php
{
using Int = long long;
using Bool = bool;

inline Int toInt(Int value)
{
    return value;
}

inline Bool toBool(Bool value)
{
    return value;
}

/**
 * 提供 TypePHP 生成代码需要的整数相等判断。
 *
 * PHPX 版本会把它实现为动态值比较；裸机版本只允许 int，因此直接使用 C++
 * 的整数比较即可。
 */
inline Bool equals(Int left, Int right)
{
    return left == right;
}
} // namespace php
