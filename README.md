# HoverRun: AT32F413 Hoverboard RC PWM Firmware

> **Modified & Enhanced by Mithlaj MT ([@mithlajmt](https://github.com/mithlajmt))**  
> Direct RC PWM dual-channel receiver control, custom AT32F413 factory protection unlocker, automated ST-Link flashing toolchain, and differential drive robotics mixer.

High-performance direct **RC PWM control firmware** and automated **ST-Link flashing/unlocking toolchain** for hoverboard mainboards equipped with the **ArteryTek AT32F413RCT7** microcontroller.

Built for mobile robots, rovers, AGVs, electric carts, and DIY vehicles.

---

## Quick Navigation
* [Hardware Wiring & Pinout](#hardware-wiring--pinout)
* [Prerequisites (What to Install)](#prerequisites-what-to-install)
* [Step-by-Step Quick Start](#step-by-step-quick-start)
* [Tuning & Configuration](#tuning--configuration)
* [Full Engineering Documentation](#full-engineering-documentation)

---

## Hardware Wiring & Pinout

### 1. Left Sensor Cable (JST 4-Pin) — RC Receiver Input
Connect your standard 2-channel hobby RC receiver (FlySky, RadioMaster, ELRS, Spektrum, etc.) to the **Left Sensor Cable**:

| Pin # | Wire Color (Typical) | MCU Pin | Function / Usage | Electrical Limits |
| :--- | :--- | :--- | :--- | :--- |
| **Pin 1** | Green / White | **PA2** | **Channel 1 (Steering)** | **3.3 V max** logic |
| **Pin 2** | Blue / Yellow | **PA3** | **Channel 2 (Throttle)** | **3.3 V max** logic |
| **Pin 3** | Black / Brown | **GND** | **Receiver Ground** | 0 V (Common Ground) |
| **Pin 4** | Red | **+15V Rail** | **Pre-regulated DC rail** | **~14 V to 15 V (DO NOT CONNECT TO RECEIVER!)** |

> [!CAUTION]
> **FATAL RECEIVER HAZARD (+15V):**
> The red wire on hoverboard sensor cables carries **~15 Volts**. Connecting this wire to an RC receiver will **instantly burn out the receiver** and can destroy the MCU. 
> 
> Power your RC receiver from an external **5V UBEC**, 5V step-down buck converter, or external battery, and connect common Ground (`GND`).

### 2. SWD Programming Header (ST-Link V2)
| Board SWD Pin | ST-Link Pin | Notes |
| :--- | :--- | :--- |
| **GND (Pin 1)** | **GND** | Common ground reference |
| **SWDIO (Pin 2)** | **SWDIO** | Serial Wire Data Input/Output |
| **SWCLK (Pin 3)** | **SWCLK** | Serial Wire Clock |
| **3.3V (Pin 4)** | **DISCONNECTED** | **DO NOT connect ST-Link 3.3V!** Board is self-powered from battery. |

---

## Prerequisites (What to Install)

> [!NOTE]
> This is an embedded C / bare-metal project for ARM microcontrollers. You do **NOT** need Node.js (`npm`), Python (`pip`), or complicated build setups.

You only need **two** standard tools on Windows:

1. **ARM GNU Toolchain (`arm-none-eabi-gcc`)**:
   * **Download**: [Arm GNU Toolchain Downloads](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads) (e.g. `arm-gnu-toolchain-*-mingw-w64-i686-arm-none-eabi.exe`).
   * **Install**: Run the installer and check the box **"Add path to environment variable"**.
2. **OpenOCD (On-Chip Debugger)**:
   * **Download**: [xPack OpenOCD Releases](https://github.com/xpack-dev-tools/openocd-xpack/releases) (download the `.zip` for Windows `win32-x64`).
   * **Setup**: Extract the zip file (e.g. into your `Downloads` folder or `C:\Program Files\`). The included scripts will automatically find it.

---

## Step-by-Step Quick Start

### 1. Clone the Repository
```powershell
git clone https://github.com/<your-username>/hoverboard-rc-firmware.git
cd hoverboard-rc-firmware
```

### 2. Compile the Firmware
Run the automated build script (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```
*This compiles `build/hover.hex` (main firmware) and `build/unlock_at32.bin` (SRAM unlock stub).*

### 3. Connect Hardware & Hold Power Button
1. Connect main battery (>36V) to hoverboard XT60 connector.
2. Connect ST-Link (GND, SWDIO, SWCLK).
3. **Press and firmly HOLD DOWN the hoverboard power button.**
   *(The power button must be held down during all flashing operations due to the MCU power latch circuit on PA5).*

### 4. Test Target Connection
```powershell
powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Check
```
*Output should show:* `SUCCESS: Target MCU detected and communicating!`

### 5. Unlock Factory Board (First Time Only)
Factory AT32 hoverboards ship with Readout Protection (FAP Level 1) locked:
```powershell
powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Unlock
```
*This executes our custom SRAM unlocker, permanently clearing protection and mass erasing the flash.*

### 6. Flash Firmware
```powershell
powershell -ExecutionPolicy Bypass -File .\flash.ps1
```
*When `FLASH SUCCESSFUL! Firmware verified and running.` appears, you can release the power button!*

---

## Tuning & Configuration

All user settings are located in [**`Inc/config.h`**](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/config.h):

* **Reverse Throttle / Steering**:
  ```c
  #define SPEED_COEFFICIENT -0.6 // Invert sign to reverse forward/backward
  #define STEER_COEFFICIENT -0.5 // Invert sign to reverse steering
  ```
* **Stick Deadband**:
  ```c
  #define PWM_DEAD_BAND 40 // Increase if wheels hum or crawl when sticks are centered
  ```
* **Different Battery Voltage**:
  ```c
  #define BAT_NUMBER_OF_CELLS 10 // Change to 7 for 24V (7s) or 12 for 48V (12s)
  ```
* **Motor Phase / Hall Sensor Mapping**:
  ```c
  #define CONFIG_HALL_IDX_LEFT  0 // 0 to 5
  #define CONFIG_HALL_IDX_RIGHT 4 // 0 to 5
  ```

---

## Full Engineering Documentation

For in-depth explanations of:
* The 96-byte ARM assembly option byte unlocker (`Src/unlock_at32.s`)
* Microsecond timer capture and differential drive mixer math
* Loss-of-signal safety cutoff and low-pass filtering
* Live UART diagnostic telemetry (`PB10` / `PB11`)

See the full manual: [**`Docs/HOVERBOARD_RC_PWM_GUIDE.md`**](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Docs/HOVERBOARD_RC_PWM_GUIDE.md).

---

## Author & Acknowledgments

### Project Modifications & RC PWM Implementation
* **Author / Maintainer**: **Mithlaj MT** ([@mithlajmt](https://github.com/mithlajmt))
* **Key Contributions & Enhancements**:
  * **RC PWM Dual-Channel Driver** ([`Src/rc_pwm.c`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/rc_pwm.c), [`Inc/rc_pwm.h`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/rc_pwm.h)): Direct microsecond timer edge capture on PA2/PA3 with failsafe loss-of-signal motor cutoff.
  * **Differential Drive Mixer**: Integrated tank-style steering mixer with slew-rate limiting, low-pass filtering, and deadband compensation.
  * **AT32F413 Hardware Unlocker** ([`Src/unlock_at32.s`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/unlock_at32.s)): Custom ARM assembly SRAM payload that permanently clears factory Flash Access Protection (FAP Level 1).
  * **Automated ST-Link Pipeline** ([`build.ps1`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/build.ps1), [`flash.ps1`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/flash.ps1)): One-command build, hardware check, option byte unlock, and flashing toolchain with OpenOCD auto-discovery.
  * **Comprehensive Documentation** ([`Docs/HOVERBOARD_RC_PWM_GUIDE.md`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Docs/HOVERBOARD_RC_PWM_GUIDE.md)): Complete electrical pinout, +15V safety hazard warnings, and future adaptation guides.

### Upstream Credits
* Base BLDC motor commutation logic and HAL drivers derived from [HoverRunFW](https://github.com/hwalli92/HoverRunFW), [thanek](https://github.com/thanek/hoverboard-firmware-hack), and the [bipropellant](https://github.com/bipropellant/bipropellant-hoverboard-firmware) community.
