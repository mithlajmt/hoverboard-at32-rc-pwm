# One-Click Build Script for HoverRunFW on Windows using ARM GCC
# Author: Mithlaj MT (@mithlajmt)
param (
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$workspaceRoot = $PSScriptRoot
$buildDir = "$workspaceRoot\build"

if ($Clean) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path $buildDir) {
        Remove-Item "$buildDir\*" -Recurse -Force
    }
    Write-Host "Clean complete." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$gcc = "arm-none-eabi-gcc.exe"
$objcopy = "arm-none-eabi-objcopy.exe"
$size = "arm-none-eabi-size.exe"

$cSources = @(
    "Drivers/HAL_Driver/src/at32f4xx_flash.c",
    "Drivers/HAL_Driver/src/at32f4xx_rcc.c",
    "Drivers/HAL_Driver/src/at32f4xx_tim.c",
    "Drivers/HAL_Driver/src/at32f4xx_gpio.c",
    "Drivers/HAL_Driver/src/at32f4xx_adc.c",
    "Drivers/HAL_Driver/src/at32f4xx_pwr.c",
    "Drivers/HAL_Driver/src/at32f4xx_usart.c",
    "Drivers/HAL_Driver/src/at32f4xx_i2c.c",
    "Drivers/HAL_Driver/src/at32f4xx_dma.c",
    "Drivers/HAL_Driver/src/at32f4xx_exti.c",
    "Drivers/HAL_Driver/src/misc.c",
    "Src/setup.c",
    "Src/main.c",
    "Src/bldc.c",
    "Src/comms.c",
    "Src/uart.c",
    "Src/at32f4xx_it.c",
    "Src/BLDC_controller_data.c",
    "Src/BLDC_controller.c",
    "Src/system_at32f4xx.c",
    "Src/rc_pwm.c"
)

$asmSources = @(
    "startup_at32f413rx_hd.s"
)

$mcuFlags = @("-mcpu=cortex-m4", "-mthumb", "-mfpu=fpv4-sp-d16", "-mfloat-abi=softfp")
$cDefs = @("-DUSE_HAL_DRIVER", "-DAT32F413Rx_HD")
$cIncludes = @(
    "-I$workspaceRoot/Inc",
    "-I$workspaceRoot/Drivers/HAL_Driver/inc",
    "-I$workspaceRoot/Drivers/CMSIS/CM4/DeviceSupport",
    "-I$workspaceRoot/Drivers/CMSIS/CM4/CoreSupport"
)

$cFlags = $mcuFlags + $cDefs + $cIncludes + @(
    "-Og",
    "-Wall",
    "-fcommon",
    "-fdata-sections",
    "-ffunction-sections",
    "-std=gnu11",
    "-g",
    "-gdwarf-2",
    "-include", "$workspaceRoot/Inc/at32f4xx_conf.h"
)

$ldScript = "$workspaceRoot/AT32F413xC_FLASH.ld"
$ldFlags = $mcuFlags + @(
    "-specs=nano.specs",
    "-T$ldScript",
    "-lc",
    "-lm",
    "-lnosys",
    "-Wl,-Map=$buildDir/hover.map,--cref",
    "-Wl,--gc-sections"
)

Write-Host "Compiling C and Assembly sources..." -ForegroundColor Cyan

$objects = @()

foreach ($src in $cSources) {
    $srcPath = "$workspaceRoot/$src"
    $objName = [System.IO.Path]::GetFileNameWithoutExtension($src) + ".o"
    $objPath = "$buildDir/$objName"
    $objects += $objPath
    
    Write-Host "  CC $src"
    & $gcc -c $cFlags $srcPath -o $objPath
}

foreach ($asm in $asmSources) {
    $asmPath = "$workspaceRoot/$asm"
    $objName = [System.IO.Path]::GetFileNameWithoutExtension($asm) + ".o"
    $objPath = "$buildDir/$objName"
    $objects += $objPath
    
    Write-Host "  AS $asm"
    & $gcc -c $mcuFlags $asmPath -o $objPath
}

Write-Host "Linking $buildDir/hover.elf..." -ForegroundColor Cyan
& $gcc $objects $ldFlags -o "$buildDir/hover.elf"

Write-Host "Creating $buildDir/hover.hex and $buildDir/hover.bin..." -ForegroundColor Cyan
& $objcopy -O ihex "$buildDir/hover.elf" "$buildDir/hover.hex"
& $objcopy -O binary -S "$buildDir/hover.elf" "$buildDir/hover.bin"

if (Test-Path "$workspaceRoot/Src/unlock_at32.s") {
    & $gcc -mcpu=cortex-m4 -mthumb -nostdlib -Ttext 0x20000000 "$workspaceRoot/Src/unlock_at32.s" -o "$buildDir/unlock_at32.elf"
    & $objcopy -O binary "$buildDir/unlock_at32.elf" "$buildDir/unlock_at32.bin"
}

Write-Host "Firmware memory footprint:" -ForegroundColor Green
& $size "$buildDir/hover.elf"

Write-Host "Build finished successfully!" -ForegroundColor Green
