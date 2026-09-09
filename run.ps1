[CmdletBinding()]
param(
    [string]$Qemu = $env:TYPEOS_QEMU,
    [switch]$NoBuild,
    [switch]$Iso,
    [string]$IsoName = 'typeos.iso'
)

$ErrorActionPreference = 'Stop'

if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -IsoName $IsoName
}

if ([string]::IsNullOrWhiteSpace($Qemu)) {
    $qemuCommand = Get-Command 'qemu-system-i386.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $qemuCommand) {
        $qemuCommand = Get-Command 'qemu-system-x86_64.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($null -eq $qemuCommand) {
        $qemuCommand = Get-Command 'qemu-system-i386' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($null -eq $qemuCommand) {
        $qemuCommand = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($null -eq $qemuCommand) {
        throw '找不到 QEMU。安装后可设置 TYPEOS_QEMU，或把 qemu-system-i386 加入 PATH。'
    }
    $Qemu = $qemuCommand.Source
}

$imageName = if ($Iso) { $IsoName } else { 'typeos.img' }
$imagePath = Join-Path $PSScriptRoot ("build\$imageName")
if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    throw "找不到启动镜像：$imagePath"
}

if ($Iso) {
    & $Qemu '-m' '32M' '-cdrom' $imagePath '-boot' 'order=d'
}
else {
    & $Qemu '-m' '32M' '-fda' $imagePath '-boot' 'order=a'
}
