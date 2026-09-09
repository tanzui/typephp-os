# TypeOS

[中文](#中文) | [English](#english)

TypeOS is an experimental, educational Linux/Unix-like operating system prototype whose main policy layer is written in TypePHP.

## 中文

### 项目简介

TypeOS 是一个用于学习操作系统启动流程、裸机硬件和 TypePHP AOT 编译的最小系统原型。当前版本通过传统 BIOS 启动，在 i386 保护模式下使用 VGA 文本模式显示终端，并提供一个由 TypePHP 生成的极简 shell。

当前版本是 <code>0.1.0</code>，目标是先把“TypePHP 代码进入真正的可启动镜像”这条链路跑通。它不是 Linux 内核，也不提供完整的 POSIX 兼容层。

### 当前功能

- BIOS 启动扇区加载内核；
- 切换到 32 位 i386 保护模式；
- VGA 文本输出和可见硬件光标；
- PS/2 键盘轮询输入；
- TypePHP 实现的命令读取、解析和分派；
- 内存中的演示目录和文件：<code>/</code>、<code>/bin</code>、<code>/etc</code>、<code>/etc/motd</code>、<code>/etc/os-release</code>；
- <code>help</code>、<code>clear</code>、<code>echo</code>、<code>ls</code>、<code>cat</code>、<code>uname</code>、<code>about</code>、<code>pwd</code>、<code>reboot</code>、<code>halt</code>；
- 生成 BIOS 可启动的软盘镜像和 El Torito ISO 镜像。

### TypePHP 在系统中的位置

TypeOS 的主体策略和 shell 逻辑位于 [typephp/kernel.php](typephp/kernel.php)，目前约 730 行 TypePHP 代码，负责：

- 启动欢迎信息和提示符；
- 键盘输入循环、回车、退格和 ASCII 字符处理；
- 命令和路径识别；
- 命令分派；
- 内存文件系统的演示内容。

只有硬件相关的部分保留为 C++/汇编：

- [kernel/hal.cpp](kernel/hal.cpp)：VGA、PS/2 键盘、重启和停机；
- [kernel/entry.S](kernel/entry.S)：保护模式入口、BSS 清零和 TypePHP 入口调用；
- [boot/boot.S](boot/boot.S)：BIOS 读盘、A20 地址线和保护模式切换。

### 编译架构

~~~text
typephp/kernel.php
        │
        │ 官方 TypePHP tpc
        ▼
TypePHP 生成的 C++ 纯标量函数
        │
        │ 裸机适配 + Clang
        ▼
TypePHP 内核策略 + C++ 硬件层 + 汇编入口
        │
        ├── build/typeos.img
        └── build/typeos.iso
~~~

TypePHP 官方普通 <code>bin</code> 模式需要 PHPX/PHP Embed 运行库，但裸机环境没有操作系统、libc 或 PHP 运行时。因此构建脚本会：

1. 调用官方 <code>tpc</code> 将 TypePHP 源码转换为 C++；
2. 保留生成文件中的纯标量函数部分；
3. 移除 PHPX/Zend 扩展注册层；
4. 使用 [kernel/freestanding_runtime.hpp](kernel/freestanding_runtime.hpp) 提供极薄的整数和布尔值适配；
5. 用 freestanding Clang/LLD 编译并链接最终内核。

这意味着 TypePHP 源码确实进入了最终镜像，C++ 只负责 TypePHP 当前不能直接操作的硬件边界。当前适配层刻意限制为 <code>int</code>、<code>bool</code> 和硬件函数调用；如果在 TypePHP 内核中加入字符串、数组或动态 PHPX 类型，构建脚本会主动报告不支持。

### 目录结构

~~~text
boot/
├── boot.S                    BIOS 启动扇区
└── boot.ld                   启动扇区链接脚本

kernel/
├── entry.S                   32 位内核入口
├── freestanding_runtime.hpp  TypePHP 裸机标量适配层
├── hal.cpp                   VGA、PS/2 键盘和复位硬件层
└── kernel.ld                 内核链接脚本

typephp/
├── hal.stub.php              硬件函数的 TypePHP 声明
├── kernel.php                TypeOS 主要 TypePHP 代码
└── project.yml               tpc 项目配置

build.ps1                     TypePHP 生成、编译、链接和镜像制作脚本
run.ps1                       QEMU 启动脚本
.gitignore                    Git 忽略规则
.gitattributes                Git 文本和二进制文件属性
~~~

<code>build/</code> 和 <code>toolchain/</code> 只作为本地构建目录存在，不提交到 Git。ISO 和软盘镜像建议作为 GitHub Release 附件发布，而不是放进源码历史。

### 构建环境

推荐环境：

- Windows 10/11；
- PowerShell 7；
- TypePHP <code>tpc</code> v0.8.0 Windows x64 工具包；
- 支持 i386 目标的 Clang、LLD 和 <code>llvm-objcopy</code>；
- QEMU、VirtualBox 或 VMware（仅运行时需要）。

TypePHP 工具包体积较大，项目的 <code>.gitignore</code> 不会提交本地工具包。当前脚本会优先查找：

~~~text
toolchain/typephp-v0.8.0/tpc_v0.8.0_windows_x64/
~~~

如果是从 GitHub 克隆的全新目录，请从 [TypePHP 官方文档](https://swoole.com/aot/zh) 获取匹配版本的工具包，然后设置：

~~~powershell
$env:TYPEOS_TPC = 'D:\tools\typephp\tpc.exe'
$env:TYPEOS_TYPEPHP_HOME = 'D:\tools\typephp'
~~~

同时确保 <code>clang.exe</code>、<code>clang++.exe</code>、<code>ld.lld.exe</code> 和 <code>llvm-objcopy.exe</code> 已加入 PATH，或者显式设置：

~~~powershell
$env:TYPEOS_CLANG = 'D:\path\to\clang.exe'
$env:TYPEOS_CLANGXX = 'D:\path\to\clang++.exe'
$env:TYPEOS_LLD = 'D:\path\to\ld.lld.exe'
$env:TYPEOS_OBJCOPY = 'D:\path\to\llvm-objcopy.exe'
~~~

### 构建镜像

在项目根目录执行：

~~~powershell
.\build.ps1
~~~

构建结果：

~~~text
build/typeos.img             1.44 MB BIOS 软盘镜像
build/typeos.iso             El Torito BIOS 启动 ISO
build/boot.bin               512 字节启动扇区
build/kernel.elf             内核 ELF 文件
build/kernel.bin             写入启动介质的内核二进制
build/typephp-generated/      tpc 生成的 C++ 和裸机适配源
~~~

如果某个虚拟机正在挂载 <code>typeos.iso</code>，Windows 可能会锁定该文件。可以使用其他输出文件名：

~~~powershell
.\build.ps1 -IsoName typeos-fixed.iso
~~~

### 在 QEMU 中运行

使用 ISO 启动：

~~~powershell
qemu-system-i386 -m 32M -cdrom build\typeos.iso -boot order=d
~~~

使用脚本启动 ISO：

~~~powershell
.\run.ps1 -Iso
~~~

使用指定名称的 ISO：

~~~powershell
.\run.ps1 -Iso -IsoName typeos-fixed.iso
~~~

也可以直接启动软盘镜像：

~~~powershell
qemu-system-i386 -m 32M -fda build\typeos.img -boot order=a
~~~

### 在 VirtualBox 或 VMware 中运行

1. 创建“其他/未知 32 位”虚拟机；
2. 关闭 UEFI 和 Secure Boot，使用传统 BIOS；
3. 将 <code>build/typeos.iso</code> 挂载到虚拟光驱；
4. 将光驱设为第一启动设备；
5. 启动虚拟机后点击控制台，使键盘输入被虚拟机捕获。

ISO 使用 El Torito 的 1.44MB 软盘仿真格式，虚拟机 BIOS 会将 ISO 中的启动软盘映射为传统 A: 盘，因此不需要额外的硬盘或文件系统。

### Shell 命令

~~~text
help
clear
echo hello
echo typephp
ls
ls /bin
ls /etc
cat /etc/motd
cat /etc/os-release
uname
about
pwd
reboot
halt
~~~

演示目录和文件由 TypePHP 固定输出，当前没有真正的磁盘文件系统，重启后内容恢复初始状态。

### 当前限制

- 只支持传统 BIOS 和 i386 保护模式；
- 不支持 UEFI、Secure Boot 或 64 位启动；
- 没有 IDT、PIC、中断、定时器、进程、用户态和权限；
- 键盘使用轮询方式，只实现英文 ASCII 输入；
- 没有磁盘驱动和真正的文件系统；
- 启动代码当前最多读取 128 个内核扇区，即 64 KB；
- TypePHP 裸机适配层暂时只支持整数、布尔值和固定硬件函数；
- 这是教学原型，不是可用于生产环境的操作系统。

### 验证情况

当前已验证：

- TypePHP 源码可以由官方 <code>tpc</code> 生成 C++；
- 生成的纯 TypePHP 函数可以使用 freestanding Clang 编译；
- 内核可以使用 LLD 链接，且没有未定义符号；
- 启动扇区为 512 字节并包含 <code>55 AA</code>；
- <code>typeos.img</code> 和 <code>typeos.iso</code> 的嵌入内容一致；
- ISO 的 El Torito 启动目录和 ISO9660 基本结构正确。

自动化 QEMU 测试尚未加入，建议在发布 Release 前至少使用 QEMU 和一种桌面虚拟机各启动一次。

### 后续计划

1. 增加 IDT、PIC 和定时器；
2. 增加简单内存分配器；
3. 将键盘改为中断驱动；
4. 增加磁盘访问和只读文件系统；
5. 设计 TypePHP 用户态程序的加载和系统调用接口；
6. 再逐步扩大 TypePHP 可使用的运行时能力。

### 发布到 GitHub

本地仓库初始化和首次提交：

~~~powershell
git init -b main
git add .
git commit -m "初始化 TypeOS 项目"
~~~

创建 GitHub 空仓库后，替换下面的地址：

~~~powershell
git remote add origin https://github.com/<your-name>/<your-repository>.git
git push -u origin main
~~~

由于 <code>.gitignore</code> 会排除构建物和本地工具链，建议将 <code>build/typeos.iso</code> 和 <code>build/typeos.img</code> 上传到 GitHub Releases。

### 许可证

当前仓库尚未选择许可证。公开发布前，请根据你的使用和再分发计划添加合适的 <code>LICENSE</code> 文件。

## English

### Overview

TypeOS is a small educational Linux/Unix-like operating system prototype. It boots through a traditional BIOS, switches to 32-bit i386 protected mode, writes to VGA text memory, reads a PS/2 keyboard, and runs a tiny shell generated from TypePHP.

The current version is <code>0.1.0</code>. The immediate goal is to prove that the main OS policy and shell logic can be written in TypePHP and compiled into a real bootable image. TypeOS is not the Linux kernel and does not provide a complete POSIX compatibility layer.

### Features

- BIOS boot sector and kernel loading;
- 32-bit i386 protected mode;
- VGA text output with a visible hardware cursor;
- Polling-based PS/2 keyboard input;
- TypePHP-based input loop, parser, and command dispatcher;
- In-memory demo directories and files: <code>/</code>, <code>/bin</code>, <code>/etc</code>, <code>/etc/motd</code>, and <code>/etc/os-release</code>;
- <code>help</code>, <code>clear</code>, <code>echo</code>, <code>ls</code>, <code>cat</code>, <code>uname</code>, <code>about</code>, <code>pwd</code>, <code>reboot</code>, and <code>halt</code>;
- BIOS-bootable floppy and El Torito ISO images.

### Where TypePHP is used

The main policy layer is [typephp/kernel.php](typephp/kernel.php). It implements the prompt, keyboard input loop, command and path recognition, command dispatch, and the in-memory demo filesystem.

The remaining C++/assembly code is limited to hardware and boot responsibilities:

- [kernel/hal.cpp](kernel/hal.cpp): VGA, PS/2 keyboard, reboot, and halt;
- [kernel/entry.S](kernel/entry.S): protected-mode entry, BSS clearing, and the TypePHP entry call;
- [boot/boot.S](boot/boot.S): BIOS disk reads, A20 setup, and the protected-mode transition.

### Build pipeline

~~~text
typephp/kernel.php
        │
        │ Official TypePHP tpc
        ▼
Pure scalar C++ generated from TypePHP
        │
        │ Freestanding adapter + Clang
        ▼
TypePHP policy + C++ HAL + assembly entry
        │
        ├── build/typeos.img
        └── build/typeos.iso
~~~

The normal TypePHP <code>bin</code> mode depends on PHPX/PHP Embed, while a BIOS bare-metal kernel has no operating system, libc, or PHP runtime. The build script therefore generates C++, keeps the pure scalar function section, removes PHPX/Zend extension-registration code, adds a minimal integer/bool adapter, and links the result as a freestanding kernel.

This is not a C++ shell pretending to be TypePHP: the TypePHP source is part of the final kernel. C++ is currently used only at the hardware boundary and for the small freestanding compatibility layer. The current adapter intentionally supports only integers, booleans, and fixed hardware calls.

### Repository layout

~~~text
boot/                       BIOS boot sector and linker script
kernel/                     Protected-mode entry, HAL, and runtime adapter
typephp/kernel.php          Main TypePHP policy and shell code
typephp/hal.stub.php        TypePHP declarations for hardware calls
typephp/project.yml         tpc project configuration
build.ps1                   TypePHP generation and image build script
run.ps1                     QEMU launcher
~~~

<code>build/</code> and <code>toolchain/</code> are local-only directories and are ignored by Git. Publish bootable images as GitHub Release assets instead of adding them to the source history.

### Requirements

- Windows 10/11;
- PowerShell 7 recommended;
- TypePHP <code>tpc</code> v0.8.0 for Windows x64;
- Clang, LLD, and <code>llvm-objcopy</code> with i386 target support;
- QEMU, VirtualBox, or VMware for runtime testing.

The local TypePHP toolkit is intentionally not committed because it contains large binary files. If you clone this repository, download the matching official toolkit from the [TypePHP documentation](https://swoole.com/aot/zh), then set:

~~~powershell
$env:TYPEOS_TPC = 'D:\tools\typephp\tpc.exe'
$env:TYPEOS_TYPEPHP_HOME = 'D:\tools\typephp'
~~~

Make sure <code>clang.exe</code>, <code>clang++.exe</code>, <code>ld.lld.exe</code>, and <code>llvm-objcopy.exe</code> are available on PATH, or set <code>TYPEOS_CLANG</code>, <code>TYPEOS_CLANGXX</code>, <code>TYPEOS_LLD</code>, and <code>TYPEOS_OBJCOPY</code>.

### Build

From the repository root:

~~~powershell
.\build.ps1
~~~

The script produces:

~~~text
build/typeos.img             1.44 MB BIOS floppy image
build/typeos.iso             El Torito BIOS bootable ISO
build/boot.bin               512-byte boot sector
build/kernel.elf             Kernel ELF file
build/kernel.bin             Kernel binary written to boot media
build/typephp-generated/      tpc-generated C++ and freestanding source
~~~

If a virtual machine has <code>typeos.iso</code> mounted and Windows locks it, use a different output name:

~~~powershell
.\build.ps1 -IsoName typeos-fixed.iso
~~~

### Run with QEMU

Boot the ISO:

~~~powershell
qemu-system-i386 -m 32M -cdrom build\typeos.iso -boot order=d
~~~

Or use the launcher:

~~~powershell
.\run.ps1 -Iso
~~~

For a custom ISO name:

~~~powershell
.\run.ps1 -Iso -IsoName typeos-fixed.iso
~~~

You can also boot the floppy image:

~~~powershell
qemu-system-i386 -m 32M -fda build\typeos.img -boot order=a
~~~

### Run with VirtualBox or VMware

Create an “Other/Unknown 32-bit” VM, disable UEFI and Secure Boot, attach <code>build/typeos.iso</code> to the virtual optical drive, and put the optical drive first in the boot order. Click the VM console after boot so that the guest captures keyboard input.

The ISO uses El Torito 1.44 MB floppy emulation. The BIOS maps the embedded floppy image as the traditional A: drive, so no additional hard disk or filesystem is required.

### Shell commands

~~~text
help
clear
echo hello
echo typephp
ls
ls /bin
ls /etc
cat /etc/motd
cat /etc/os-release
uname
about
pwd
reboot
halt
~~~

The directories and files are fixed TypePHP output for demonstration purposes. There is no real disk filesystem yet, and the contents reset after reboot.

### Limitations

- Traditional BIOS and 32-bit i386 protected mode only;
- No UEFI, Secure Boot, or 64-bit boot path;
- No IDT, PIC, interrupts, timers, processes, user mode, or permissions;
- Polling-based keyboard input with English ASCII support only;
- No disk driver or real filesystem;
- The bootloader currently reads at most 128 kernel sectors, or 64 KB;
- The TypePHP bare-metal adapter currently supports only integers, booleans, and fixed hardware calls;
- This is an educational prototype, not a production operating system.

### Verification

The following has been verified:

- Official <code>tpc</code> generates C++ from the TypePHP sources;
- The pure TypePHP function section compiles with freestanding Clang;
- The kernel links with LLD without undefined symbols;
- The boot sector is exactly 512 bytes and ends in <code>55 AA</code>;
- The floppy image and ISO contain identical boot media data;
- The ISO contains a valid El Torito boot catalog and basic ISO9660 structures.

Automated QEMU boot testing is not configured yet. Before publishing a Release, test the image in QEMU and at least one desktop virtualization product.

### Roadmap

1. Add an IDT, PIC, and timer;
2. Add a small memory allocator;
3. Move keyboard input to interrupts;
4. Add disk access and a read-only filesystem;
5. Design a TypePHP user-mode loader and syscall ABI;
6. Gradually expand the TypePHP runtime available to the kernel and user programs.

### Publishing to GitHub

Initialize and create the first local commit:

~~~powershell
git init -b main
git add .
git commit -m "初始化 TypeOS 项目"
~~~

After creating an empty GitHub repository, replace the placeholder URL:

~~~powershell
git remote add origin https://github.com/<your-name>/<your-repository>.git
git push -u origin main
~~~

Because <code>.gitignore</code> excludes build products and the local TypePHP toolkit, publish <code>build/typeos.iso</code> and <code>build/typeos.img</code> as GitHub Release assets.

### License

No license has been selected yet. Add an appropriate <code>LICENSE</code> file before public reuse or redistribution.
