[CmdletBinding()]
param(
    [string]$Clang = $env:TYPEOS_CLANG,
    [string]$Clangxx = $env:TYPEOS_CLANGXX,
    [string]$Lld = $env:TYPEOS_LLD,
    [string]$Objcopy = $env:TYPEOS_OBJCOPY,
    [string]$TypePhpTpc = $env:TYPEOS_TPC,
    [string]$TypePhpHome = $env:TYPEOS_TYPEPHP_HOME,
    [string]$BuildDir = (Join-Path $PSScriptRoot 'build'),
    [string]$IsoName = 'typeos.iso'
)

$ErrorActionPreference = 'Stop'

# <summary>
# 查找构建 TypeOS 所需的本地工具，并优先使用调用者指定的路径。
# </summary>
# <param name="Preferred">调用者明确指定的命令名或文件路径。</param>
# <param name="Names">按优先顺序尝试的工具名称。</param>
# <returns>可以执行的工具完整路径。</returns>
function Resolve-TypeOsTool {
    param(
        [string]$Preferred,
        [string[]]$Names
    )

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        $preferredCommand = Get-Command $Preferred -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $preferredCommand) {
            return $preferredCommand.Source
        }
        if (Test-Path -LiteralPath $Preferred -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Preferred).Path
        }
    }

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "找不到构建工具：$($Names -join ', ')。可以通过 TYPEOS_CLANG、TYPEOS_CLANGXX、TYPEOS_LLD、TYPEOS_OBJCOPY 指定路径。"
}

# <summary>
# 执行一个本地构建命令，并在命令失败时中止镜像构建。
# </summary>
# <param name="FilePath">可执行文件完整路径。</param>
# <param name="Arguments">传给可执行文件的参数数组。</param>
function Invoke-TypeOsTool {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "构建命令失败（退出码 $LASTEXITCODE）：$FilePath $($Arguments -join ' ')"
    }
}

# <summary>
# 把 TypePHP 生成文件中的纯函数部分包装成可供裸机链接的 C++ 源文件。
# </summary>
# <param name="GeneratedSourcePath">官方 tpc 生成的 kernel.cc 路径。</param>
# <param name="OutputPath">要写入的裸机适配 C++ 文件路径。</param>
function New-TypeOsFreestandingSource {
    param(
        [string]$GeneratedSourcePath,
        [string]$OutputPath
    )

    $generatedText = [IO.File]::ReadAllText($GeneratedSourcePath)
    $wrapperMarker = $generatedText.IndexOf('ZEND_FUNCTION')
    if ($wrapperMarker -lt 0) {
        throw "TypePHP 生成文件中没有找到 PHPX 包装层分界：$GeneratedSourcePath"
    }

    # tpc 生成文件前半部分是 TypePHP 函数体，后半部分是 PHP 扩展注册代码。
    # 裸机只保留前半部分，并移除 PHPX 头文件，避免把宿主 PHP 运行时带进内核。
    $pureTypePhpText = $generatedText.Substring(0, $wrapperMarker)
    $pureTypePhpText = [regex]::Replace($pureTypePhpText, '(?m)^#include[^\r\n]*\r?\n', '')
    if ($pureTypePhpText -notmatch '(?m)^void php_main\s*\(') {
        throw "TypePHP 生成文件中没有找到 main 函数：$GeneratedSourcePath"
    }
    if ($pureTypePhpText -match 'php::Var|php::Str|ZEND_|zend_|phpx') {
        throw 'TypePHP 内核使用了当前裸机适配层不支持的动态 PHPX 类型或扩展代码。'
    }

    $header = @"
#include "freestanding_runtime.hpp"

extern "C" {
void php_hal_putc(php::Int value);
php::Int php_hal_getc();
void php_hal_clear();
void php_hal_reboot();
void php_hal_halt();
}

// TypePHP 源码允许函数先调用后定义，PHPX 头文件原本会提供这个声明。
void php_execute_command(php::Int commandHash, php::Int commandLength, php::Int mode, php::Int argumentHash, php::Int argumentLength);

"@
    $footer = @"

extern "C" void typephp_kernel_main()
{
    php_main();
}
"@

    $outputDirectory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    [IO.File]::WriteAllText(
        $OutputPath,
        $header + $pureTypePhpText + $footer,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

# <summary>
# 向字节缓冲区写入 ISO9660 使用的小端整数。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Value">要写入的整数。</param>
function Set-TypeOsLe16 {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes([uint16]$Value)
    $Buffer[$Offset] = $bytes[0]
    $Buffer[$Offset + 1] = $bytes[1]
}

# <summary>
# 向字节缓冲区写入 ISO9660 使用的小端 32 位整数。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Value">要写入的整数。</param>
function Set-TypeOsLe32 {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes([uint32]$Value)
    $Buffer[$Offset] = $bytes[0]
    $Buffer[$Offset + 1] = $bytes[1]
    $Buffer[$Offset + 2] = $bytes[2]
    $Buffer[$Offset + 3] = $bytes[3]
}

# <summary>
# 向字节缓冲区写入 ISO9660 使用的大端 32 位整数。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Value">要写入的整数。</param>
function Set-TypeOsBe32 {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes([uint32]$Value)
    $Buffer[$Offset] = $bytes[3]
    $Buffer[$Offset + 1] = $bytes[2]
    $Buffer[$Offset + 2] = $bytes[1]
    $Buffer[$Offset + 3] = $bytes[0]
}

# <summary>
# 向字节缓冲区写入 ISO9660 的小端/大端成对整数。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Value">要写入的整数。</param>
function Set-TypeOsBothEndian16 {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes([uint16]$Value)
    $Buffer[$Offset] = $bytes[0]
    $Buffer[$Offset + 1] = $bytes[1]
    $Buffer[$Offset + 2] = $bytes[1]
    $Buffer[$Offset + 3] = $bytes[0]
}

# <summary>
# 向字节缓冲区写入 ISO9660 的小端/大端成对 32 位整数。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Value">要写入的整数。</param>
function Set-TypeOsBothEndian32 {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes([uint32]$Value)
    $Buffer[$Offset] = $bytes[0]
    $Buffer[$Offset + 1] = $bytes[1]
    $Buffer[$Offset + 2] = $bytes[2]
    $Buffer[$Offset + 3] = $bytes[3]
    $Buffer[$Offset + 4] = $bytes[3]
    $Buffer[$Offset + 5] = $bytes[2]
    $Buffer[$Offset + 6] = $bytes[1]
    $Buffer[$Offset + 7] = $bytes[0]
}

# <summary>
# 向 ISO9660 固定长度文本字段写入 ASCII，并用指定字节填充剩余空间。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">字段起始位置。</param>
# <param name="Length">字段长度。</param>
# <param name="Value">要写入的 ASCII 文本。</param>
# <param name="PadByte">剩余空间使用的填充值。</param>
function Set-TypeOsAscii {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Length,
        [string]$Value,
        [byte]$PadByte = 0x20
    )

    for ($index = 0; $index -lt $Length; ++$index) {
        $Buffer[$Offset + $index] = $PadByte
    }

    $bytes = [Text.Encoding]::ASCII.GetBytes($Value)
    $copyLength = [Math]::Min($bytes.Length, $Length)
    if ($copyLength -gt 0) {
        [Array]::Copy($bytes, 0, $Buffer, $Offset, $copyLength)
    }
}

# <summary>
# 写入 ISO9660 路径表中的一个目录记录。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">记录起始位置。</param>
# <param name="DirectoryLba">根目录所在逻辑块号。</param>
# <param name="BigEndian">是否使用大端字段。</param>
function Set-TypeOsPathTableRecord {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$DirectoryLba,
        [switch]$BigEndian
    )

    $Buffer[$Offset] = 1
    $Buffer[$Offset + 1] = 0
    $bytes = [BitConverter]::GetBytes([uint32]$DirectoryLba)
    if ($BigEndian) {
        $Buffer[$Offset + 2] = $bytes[3]
        $Buffer[$Offset + 3] = $bytes[2]
        $Buffer[$Offset + 4] = $bytes[1]
        $Buffer[$Offset + 5] = $bytes[0]
    }
    else {
        $Buffer[$Offset + 2] = $bytes[0]
        $Buffer[$Offset + 3] = $bytes[1]
        $Buffer[$Offset + 4] = $bytes[2]
        $Buffer[$Offset + 5] = $bytes[3]
    }

    if ($BigEndian) {
        $Buffer[$Offset + 6] = 0
        $Buffer[$Offset + 7] = 1
    }
    else {
        $Buffer[$Offset + 6] = 1
        $Buffer[$Offset + 7] = 0
    }
    $Buffer[$Offset + 8] = 0
    $Buffer[$Offset + 9] = 0
}

# <summary>
# 写入 ISO9660 目录中的一个文件或目录记录。
# </summary>
# <param name="Buffer">目标 ISO 字节缓冲区。</param>
# <param name="Offset">记录起始位置。</param>
# <param name="ExtentLba">文件或目录所在逻辑块号。</param>
# <param name="DataLength">文件或目录长度。</param>
# <param name="Flags">ISO9660 文件标志，目录使用 0x02。</param>
# <param name="FileIdentifier">文件标识符字节。</param>
function Set-TypeOsDirectoryRecord {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$ExtentLba,
        [int]$DataLength,
        [byte]$Flags,
        [byte[]]$FileIdentifier
    )

    $identifierLength = $FileIdentifier.Length
    $paddingLength = if (($identifierLength % 2) -eq 0) { 1 } else { 0 }
    $recordLength = 33 + $identifierLength + $paddingLength
    $Buffer[$Offset] = [byte]$recordLength
    $Buffer[$Offset + 1] = 0
    Set-TypeOsBothEndian32 -Buffer $Buffer -Offset ($Offset + 2) -Value $ExtentLba
    Set-TypeOsBothEndian32 -Buffer $Buffer -Offset ($Offset + 10) -Value $DataLength

    # 目录日期采用 ISO9660 的 7 字节二进制格式；固定为构建时的无时区时间即可。
    $recordDate = [byte[]](126, 1, 1, 0, 0, 0, 0)
    [Array]::Copy($recordDate, 0, $Buffer, $Offset + 18, $recordDate.Length)
    $Buffer[$Offset + 25] = $Flags
    $Buffer[$Offset + 26] = 0
    $Buffer[$Offset + 27] = 0
    Set-TypeOsBothEndian16 -Buffer $Buffer -Offset ($Offset + 28) -Value 1
    $Buffer[$Offset + 32] = [byte]$identifierLength
    [Array]::Copy($FileIdentifier, 0, $Buffer, $Offset + 33, $identifierLength)
    if ($paddingLength -eq 1) {
        $Buffer[$Offset + 33 + $identifierLength] = 0
    }
}

# <summary>
# 使用 El Torito 软盘仿真格式，把现有 1.44MB 启动软盘包装成 BIOS 可启动 ISO。
# </summary>
# <param name="FloppyImagePath">已经生成的 1.44MB 软盘镜像路径。</param>
# <param name="OutputPath">ISO 输出路径。</param>
function New-TypeOsIsoImage {
    param(
        [string]$FloppyImagePath,
        [string]$OutputPath
    )

    $logicalBlockSize = 2048
    $floppyBytes = [IO.File]::ReadAllBytes($FloppyImagePath)
    if ($floppyBytes.Length -ne 1474560) {
        throw "ISO 的软盘仿真镜像必须是 1.44MB，当前大小为 $($floppyBytes.Length) 字节。"
    }

    # 0-15 是 ISO 系统区；16-18 是卷描述符；19 是启动目录；20-23 是
    # 路径表、根目录；从 23 开始放入完整的 1.44MB 软盘镜像。
    $bootCatalogLba = 19
    $littleEndianPathTableLba = 20
    $bigEndianPathTableLba = 21
    $rootDirectoryLba = 22
    $floppyImageLba = 23
    $floppySectorCount = [int][Math]::Ceiling($floppyBytes.Length / $logicalBlockSize)
    $totalSectorCount = $floppyImageLba + $floppySectorCount
    $isoBytes = New-Object -TypeName 'System.Byte[]' -ArgumentList ($totalSectorCount * $logicalBlockSize)

    $pvdOffset = 16 * $logicalBlockSize
    $isoBytes[$pvdOffset] = 1
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 1) -Length 5 -Value 'CD001' -PadByte 0
    $isoBytes[$pvdOffset + 6] = 1
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 8) -Length 32 -Value 'TYPEOS'
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 40) -Length 32 -Value 'TYPEOS_BOOT'
    Set-TypeOsBothEndian32 -Buffer $isoBytes -Offset ($pvdOffset + 80) -Value $totalSectorCount
    Set-TypeOsBothEndian16 -Buffer $isoBytes -Offset ($pvdOffset + 120) -Value 1
    Set-TypeOsBothEndian16 -Buffer $isoBytes -Offset ($pvdOffset + 124) -Value 1
    Set-TypeOsBothEndian16 -Buffer $isoBytes -Offset ($pvdOffset + 128) -Value $logicalBlockSize
    Set-TypeOsBothEndian32 -Buffer $isoBytes -Offset ($pvdOffset + 132) -Value 10
    Set-TypeOsLe32 -Buffer $isoBytes -Offset ($pvdOffset + 140) -Value $littleEndianPathTableLba
    Set-TypeOsLe32 -Buffer $isoBytes -Offset ($pvdOffset + 144) -Value 0
    Set-TypeOsBe32 -Buffer $isoBytes -Offset ($pvdOffset + 148) -Value $bigEndianPathTableLba
    Set-TypeOsBe32 -Buffer $isoBytes -Offset ($pvdOffset + 152) -Value 0
    Set-TypeOsDirectoryRecord -Buffer $isoBytes -Offset ($pvdOffset + 156) -ExtentLba $rootDirectoryLba -DataLength $logicalBlockSize -Flags 0x02 -FileIdentifier ([byte[]](0))
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 190) -Length 128 -Value 'TYPEOS'
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 318) -Length 128 -Value 'TypeOS project'
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 446) -Length 128 -Value 'TypeOS build script'
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 574) -Length 128 -Value 'TypeOS'
    $volumeDate = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssff', [Globalization.CultureInfo]::InvariantCulture) + '0'
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 813) -Length 17 -Value $volumeDate -PadByte 0
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 830) -Length 17 -Value $volumeDate -PadByte 0
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($pvdOffset + 864) -Length 17 -Value $volumeDate -PadByte 0
    $isoBytes[$pvdOffset + 881] = 1

    $bootRecordOffset = 17 * $logicalBlockSize
    $isoBytes[$bootRecordOffset] = 0
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($bootRecordOffset + 1) -Length 5 -Value 'CD001' -PadByte 0
    $isoBytes[$bootRecordOffset + 6] = 1
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($bootRecordOffset + 7) -Length 32 -Value 'EL TORITO SPECIFICATION'
    Set-TypeOsLe32 -Buffer $isoBytes -Offset ($bootRecordOffset + 71) -Value $bootCatalogLba

    $terminatorOffset = 18 * $logicalBlockSize
    $isoBytes[$terminatorOffset] = 0xff
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($terminatorOffset + 1) -Length 5 -Value 'CD001' -PadByte 0
    $isoBytes[$terminatorOffset + 6] = 1

    $catalogOffset = $bootCatalogLba * $logicalBlockSize
    $isoBytes[$catalogOffset] = 1
    $isoBytes[$catalogOffset + 1] = 0
    Set-TypeOsAscii -Buffer $isoBytes -Offset ($catalogOffset + 4) -Length 24 -Value 'TypeOS BIOS boot catalog'
    $isoBytes[$catalogOffset + 30] = 0x55
    $isoBytes[$catalogOffset + 31] = 0xaa
    $checksum = 0
    for ($index = 0; $index -lt 32; $index += 2) {
        if ($index -ne 28) {
            $checksum += [int]$isoBytes[$catalogOffset + $index] + (([int]$isoBytes[$catalogOffset + $index + 1]) -shl 8)
        }
    }
    Set-TypeOsLe16 -Buffer $isoBytes -Offset ($catalogOffset + 28) -Value ((0 - $checksum) -band 0xffff)

    # 初始启动项使用 1.44MB 软盘仿真，BIOS 会把后面的完整软盘镜像映射成 A: 盘。
    $initialEntryOffset = $catalogOffset + 32
    $isoBytes[$initialEntryOffset] = 0x88
    $isoBytes[$initialEntryOffset + 1] = 0x02
    $isoBytes[$initialEntryOffset + 2] = 0
    $isoBytes[$initialEntryOffset + 3] = 0
    Set-TypeOsLe16 -Buffer $isoBytes -Offset ($initialEntryOffset + 6) -Value 1
    Set-TypeOsLe32 -Buffer $isoBytes -Offset ($initialEntryOffset + 8) -Value $floppyImageLba

    Set-TypeOsPathTableRecord -Buffer $isoBytes -Offset ($littleEndianPathTableLba * $logicalBlockSize) -DirectoryLba $rootDirectoryLba
    Set-TypeOsPathTableRecord -Buffer $isoBytes -Offset ($bigEndianPathTableLba * $logicalBlockSize) -DirectoryLba $rootDirectoryLba -BigEndian

    $rootDirectoryOffset = $rootDirectoryLba * $logicalBlockSize
    Set-TypeOsDirectoryRecord -Buffer $isoBytes -Offset $rootDirectoryOffset -ExtentLba $rootDirectoryLba -DataLength $logicalBlockSize -Flags 0x02 -FileIdentifier ([byte[]](0))
    Set-TypeOsDirectoryRecord -Buffer $isoBytes -Offset ($rootDirectoryOffset + 34) -ExtentLba $rootDirectoryLba -DataLength $logicalBlockSize -Flags 0x02 -FileIdentifier ([byte[]](1))
    $floppyFileIdentifier = [Text.Encoding]::ASCII.GetBytes('TYPEOS.IMG;1')
    Set-TypeOsDirectoryRecord -Buffer $isoBytes -Offset ($rootDirectoryOffset + 68) -ExtentLba $floppyImageLba -DataLength $floppyBytes.Length -Flags 0 -FileIdentifier $floppyFileIdentifier
    [Array]::Copy($floppyBytes, 0, $isoBytes, $floppyImageLba * $logicalBlockSize, $floppyBytes.Length)

    $outputDirectory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    [IO.File]::WriteAllBytes($OutputPath, $isoBytes)
}

$clangPath = Resolve-TypeOsTool -Preferred $Clang -Names @('clang.exe', 'clang')
$clangDirectory = Split-Path -Parent $clangPath

if ([string]::IsNullOrWhiteSpace($Clangxx) -and (Test-Path -LiteralPath (Join-Path $clangDirectory 'clang++.exe'))) {
    $Clangxx = Join-Path $clangDirectory 'clang++.exe'
}
if ([string]::IsNullOrWhiteSpace($Lld) -and (Test-Path -LiteralPath (Join-Path $clangDirectory 'ld.lld.exe'))) {
    $Lld = Join-Path $clangDirectory 'ld.lld.exe'
}
if ([string]::IsNullOrWhiteSpace($Objcopy) -and (Test-Path -LiteralPath (Join-Path $clangDirectory 'llvm-objcopy.exe'))) {
    $Objcopy = Join-Path $clangDirectory 'llvm-objcopy.exe'
}

$clangxxPath = Resolve-TypeOsTool -Preferred $Clangxx -Names @('clang++.exe', 'clang++')
$lldPath = Resolve-TypeOsTool -Preferred $Lld -Names @('ld.lld.exe', 'ld.lld')
$objcopyPath = Resolve-TypeOsTool -Preferred $Objcopy -Names @('llvm-objcopy.exe', 'llvm-objcopy')

$rootDirectory = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$buildDirectory = [IO.Path]::GetFullPath($BuildDir)
if ([string]::IsNullOrWhiteSpace($IsoName) -or [IO.Path]::GetFileName($IsoName) -ne $IsoName) {
    throw 'IsoName 只能是当前 build 目录下的文件名，不能包含目录。'
}
$objectDirectory = Join-Path $buildDirectory 'obj'
$typePhpGeneratedDirectory = Join-Path $buildDirectory 'typephp-generated'
$typePhpLinkDirectory = Join-Path $buildDirectory 'typephp-link'
New-Item -ItemType Directory -Force -Path $objectDirectory | Out-Null

if ([string]::IsNullOrWhiteSpace($TypePhpTpc)) {
    $localTypePhpTpc = Join-Path $rootDirectory 'toolchain\typephp-v0.8.0\tpc_v0.8.0_windows_x64\tpc.exe'
    if (Test-Path -LiteralPath $localTypePhpTpc -PathType Leaf) {
        $TypePhpTpc = $localTypePhpTpc
    }
    else {
        $TypePhpTpc = 'tpc.exe'
    }
}
$typePhpPath = Resolve-TypeOsTool -Preferred $TypePhpTpc -Names @('tpc.exe', 'tpc')

if ([string]::IsNullOrWhiteSpace($TypePhpHome)) {
    $TypePhpHome = Split-Path -Parent $typePhpPath
}
$typePhpHomePath = (Resolve-Path -LiteralPath $TypePhpHome).Path
$typePhpRuntimePath = Join-Path $typePhpHomePath 'phpx'
if (-not (Test-Path -LiteralPath $typePhpRuntimePath -PathType Container)) {
    throw "找不到 TypePHP 的 PHPX 运行库目录：$typePhpRuntimePath"
}
New-Item -ItemType Directory -Force -Path $typePhpGeneratedDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $typePhpLinkDirectory | Out-Null

# tpc v0.8.0 在 Windows 的 dry 模式仍会探测 link.exe。这里使用同一套 LLVM
# 链接器提供兼容入口，生成阶段不会真正把 PHPX 扩展链接进 TypeOS。
$typePhpLinkShim = Join-Path $typePhpLinkDirectory 'link.exe'
Copy-Item -LiteralPath $lldPath -Destination $typePhpLinkShim -Force

$bootObject = Join-Path $objectDirectory 'boot.o'
$bootBinary = Join-Path $buildDirectory 'boot.bin'
$entryObject = Join-Path $objectDirectory 'entry.o'
$halObject = Join-Path $objectDirectory 'hal.o'
$typePhpKernelSource = Join-Path $typePhpGeneratedDirectory 'typephp-kernel.cpp'
$typePhpKernelObject = Join-Path $objectDirectory 'typephp-kernel.o'
$kernelElf = Join-Path $buildDirectory 'kernel.elf'
$kernelBinary = Join-Path $buildDirectory 'kernel.bin'
$imagePath = Join-Path $buildDirectory 'typeos.img'
$isoPath = Join-Path $buildDirectory $IsoName

Write-Host '编译 BIOS 启动扇区...'
Invoke-TypeOsTool $clangPath @(
    '-target', 'i386-unknown-none-elf',
    '-m16',
    '-ffreestanding',
    '-fno-builtin',
    '-c',
    (Join-Path $rootDirectory 'boot\boot.S'),
    '-o', $bootObject
)

Invoke-TypeOsTool $lldPath @(
    '-m', 'elf_i386',
    '-T', (Join-Path $rootDirectory 'boot\boot.ld'),
    '--oformat', 'binary',
    '-o', $bootBinary,
    $bootObject
)

Write-Host '生成 TypePHP 内核策略层...'
$oldTypePhpHome = $env:TYPEPHP_HOME
$oldPhpHome = $env:PHP_HOME
$oldPhpxHome = $env:PHPX_HOME
$oldPath = $env:Path
try {
    $env:TYPEPHP_HOME = $typePhpHomePath
    $env:PHP_HOME = $typePhpHomePath
    $env:PHPX_HOME = $typePhpRuntimePath
    $env:Path = "$typePhpLinkDirectory;$oldPath"

    Invoke-TypeOsTool $typePhpPath @(
        (Join-Path $rootDirectory 'typephp'),
        '--dry',
        '--force',
        '--build-dir', $typePhpGeneratedDirectory,
        '--compiler', $clangxxPath,
        '--no-progress'
    )
}
finally {
    $env:TYPEPHP_HOME = $oldTypePhpHome
    $env:PHP_HOME = $oldPhpHome
    $env:PHPX_HOME = $oldPhpxHome
    $env:Path = $oldPath
}

$generatedKernelPath = Get-ChildItem -LiteralPath $typePhpGeneratedDirectory -Recurse -Filter 'kernel.cc' -File |
    Select-Object -First 1
if ($null -eq $generatedKernelPath) {
    throw "TypePHP 没有生成 kernel.cc：$typePhpGeneratedDirectory"
}
New-TypeOsFreestandingSource -GeneratedSourcePath $generatedKernelPath.FullName -OutputPath $typePhpKernelSource

Write-Host '编译 freestanding 启动入口、硬件层和 TypePHP 生成代码...'
Invoke-TypeOsTool $clangPath @(
    '-target', 'i386-unknown-none-elf',
    '-m32',
    '-ffreestanding',
    '-fno-builtin',
    '-fno-stack-protector',
    '-fno-exceptions',
    '-fno-rtti',
    '-fno-use-cxa-atexit',
    '-mno-sse',
    '-mno-mmx',
    '-mno-sse2',
    '-O2',
    '-Wall',
    '-Wextra',
    '-std=c++17',
    '-c',
    (Join-Path $rootDirectory 'kernel\entry.S'),
    '-o', $entryObject
)

Invoke-TypeOsTool $clangxxPath @(
    '-target', 'i386-unknown-none-elf',
    '-m32',
    '-ffreestanding',
    '-fno-builtin',
    '-fno-stack-protector',
    '-fno-exceptions',
    '-fno-rtti',
    '-fno-use-cxa-atexit',
    '-mno-sse',
    '-mno-mmx',
    '-mno-sse2',
    '-O2',
    '-Wall',
    '-Wextra',
    '-std=c++17',
    '-c',
    (Join-Path $rootDirectory 'kernel\hal.cpp'),
    '-o', $halObject
)

Invoke-TypeOsTool $clangxxPath @(
    '-target', 'i386-unknown-none-elf',
    '-m32',
    '-ffreestanding',
    '-fno-builtin',
    '-fno-stack-protector',
    '-fno-exceptions',
    '-fno-rtti',
    '-fno-use-cxa-atexit',
    '-mno-sse',
    '-mno-mmx',
    '-mno-sse2',
    '-O2',
    '-Wall',
    '-Wextra',
    '-std=c++17',
    '-I', (Join-Path $rootDirectory 'kernel'),
    '-c',
    $typePhpKernelSource,
    '-o', $typePhpKernelObject
)

Invoke-TypeOsTool $lldPath @(
    '-m', 'elf_i386',
    '-T', (Join-Path $rootDirectory 'kernel\kernel.ld'),
    '-o', $kernelElf,
    $entryObject,
    $halObject,
    $typePhpKernelObject
)

Invoke-TypeOsTool $objcopyPath @(
    '-O', 'binary',
    $kernelElf,
    $kernelBinary
)

$bootBytes = [IO.File]::ReadAllBytes($bootBinary)
if ($bootBytes.Length -ne 512 -or $bootBytes[510] -ne 0x55 -or $bootBytes[511] -ne 0xaa) {
    throw '启动扇区校验失败：必须正好 512 字节，并以 55 AA 结尾。'
}

$kernelBytes = [IO.File]::ReadAllBytes($kernelBinary)
$kernelSectorCount = 128
$maximumKernelBytes = $kernelSectorCount * 512
if ($kernelBytes.Length -gt $maximumKernelBytes) {
    throw "内核大小为 $($kernelBytes.Length) 字节，超过启动扇区当前读取上限 $maximumKernelBytes 字节。"
}

# 创建 1.44MB 软盘镜像。镜像内只有启动扇区和内核，其余空间保持为零。
$imageStream = [IO.File]::Open(
    $imagePath,
    [IO.FileMode]::Create,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
try {
    $imageStream.SetLength(1474560)
    $imageStream.Position = 0
    $imageStream.Write($bootBytes, 0, $bootBytes.Length)
    $imageStream.Position = 512
    $imageStream.Write($kernelBytes, 0, $kernelBytes.Length)
}
finally {
    $imageStream.Dispose()
}

New-TypeOsIsoImage -FloppyImagePath $imagePath -OutputPath $isoPath

Write-Host "构建完成：$imagePath"
Write-Host "ISO 完成：$isoPath"
Write-Host "内核大小：$($kernelBytes.Length) 字节；启动扇区读取上限：$maximumKernelBytes 字节。"
