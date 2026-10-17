# One-Click Flash Script for AT32F413RCT7 Hoverboard Board using ST-Link
param (
    [switch]$Unlock,
    [switch]$Check,
    [string]$OpenOcdPath = "openocd.exe",
    [string]$OpenOcdScriptsPath
)

$workspaceRoot = $PSScriptRoot
$hexFile = "$workspaceRoot\build\hover.hex"

$openocdCommand = Get-Command $OpenOcdPath -ErrorAction SilentlyContinue
if ($openocdCommand) {
    $openocdExe = $openocdCommand.Source
} elseif (Test-Path $OpenOcdPath) {
    $openocdExe = (Resolve-Path $OpenOcdPath).Path
} else {
    # Check common fallback locations (e.g. xpack-openocd in Downloads)
    $fallbackCandidates = @(
        "$env:USERPROFILE\Downloads\xpack-openocd-*\xpack-openocd-*\bin\openocd.exe",
        "$env:USERPROFILE\Downloads\openocd-*\bin\openocd.exe",
        "C:\Program Files\OpenOCD\bin\openocd.exe",
        "C:\OpenOCD\bin\openocd.exe"
    )
    foreach ($pattern in $fallbackCandidates) {
        $found = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $openocdExe = $found.Path
            Write-Host "Auto-detected OpenOCD: $openocdExe" -ForegroundColor Cyan
            break
        }
    }
    if (-not $openocdExe) {
        Write-Host "ERROR: OpenOCD not found. Install it, add it to PATH, or pass -OpenOcdPath." -ForegroundColor Red
        exit 1
    }
}

$openocdScriptArgs = @()
if ($OpenOcdScriptsPath) {
    if (-not (Test-Path $OpenOcdScriptsPath -PathType Container)) {
        Write-Host "ERROR: OpenOCD scripts directory not found: $OpenOcdScriptsPath" -ForegroundColor Red
        exit 1
    }
    $openocdScriptArgs = @("-s", (Resolve-Path $OpenOcdScriptsPath).Path)
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  AT32F413RCT7 Hoverboard Flashing Utility (ST-Link)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "CRITICAL PRE-FLIGHT CHECKLIST:" -ForegroundColor Yellow
Write-Host " 1. Battery (>36V) MUST be plugged into the hoverboard XT60."
Write-Host " 2. Connect ST-Link GND, SWDIO, and SWCLK to the SWD header."
Write-Host "    (Do NOT connect ST-Link 3.3V pin to the board!)"
Write-Host " 3. HOLD DOWN the Power Button continuously right now!" -ForegroundColor Red
Write-Host "==========================================================" -ForegroundColor Cyan

if ($Check) {
    Write-Host "Checking target connection..." -ForegroundColor Yellow
    Push-Location $workspaceRoot
    & $openocdExe @openocdScriptArgs `
        -f interface/stlink.cfg `
        -c "transport select swd; adapter speed 500" `
        -f target/artery/at32f4x.cfg `
        -c "init" `
        -c "targets" `
        -c "shutdown"
    $openocdExitCode = $LASTEXITCODE
    Pop-Location

    if ($openocdExitCode -eq 0) {
        Write-Host "SUCCESS: Target MCU detected and communicating!" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Unable to connect to target MCU." -ForegroundColor Red
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host " - Is the power button being held down firmly?"
        Write-Host " - Is the 36V-42V battery plugged in?"
        Write-Host " - Are SWDIO and SWCLK connected to the right pins?"
    }
    exit $openocdExitCode
}

if ($Unlock) {
    Write-Host "[1/2] Disabling Flash Access Protection (Unlocking) & Mass Erasing..." -ForegroundColor Yellow
    Push-Location $workspaceRoot
    & $openocdExe @openocdScriptArgs `
        -f interface/stlink.cfg `
        -c "transport select swd; adapter speed 500" `
        -f target/artery/at32f4x.cfg `
        -f "$workspaceRoot\unlock_target.cfg"
    $openocdExitCode = $LASTEXITCODE
    Pop-Location

    if ($openocdExitCode -eq 0) {
        Write-Host "SUCCESS: Chip unlocked and erased successfully!" -ForegroundColor Green
        Write-Host "You can now flash the firmware using: .\flash.ps1" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Unlocking failed with exit code $openocdExitCode" -ForegroundColor Red
        Write-Host "Ensure the power button is held down while running the command." -ForegroundColor Yellow
    }
    exit $openocdExitCode
}

if (-not (Test-Path $hexFile)) {
    Write-Host "ERROR: Binary $hexFile not found! Please run .\build.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Flashing $hexFile..." -ForegroundColor Green
Push-Location $workspaceRoot
& $openocdExe @openocdScriptArgs `
    -f interface/stlink.cfg `
    -c "transport select swd; adapter speed 500" `
    -f target/artery/at32f4x.cfg `
    -f "$workspaceRoot\stlink-command.cfg"
$openocdExitCode = $LASTEXITCODE
Pop-Location

if ($openocdExitCode -eq 0) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " FLASH SUCCESSFUL! Firmware verified and running." -ForegroundColor Green
    Write-Host " You may now release the power button." -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Cyan
} else {
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host " FLASH FAILED! Exit code: $openocdExitCode" -ForegroundColor Red
    Write-Host " The firmware was NOT written to the board." -ForegroundColor Red
    Write-Host " Please hold the power button down and verify your SWD wiring." -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Red
    exit $openocdExitCode
}
