# HoverRun Hoverboard Controller: RC PWM Operation & Engineering Guide

> **Author & Implementation: Mithlaj MT ([@mithlajmt](https://github.com/mithlajmt))**  
> Custom RC PWM firmware, AT32F413 hardware unlocker, and ST-Link flashing toolchain.

This document is a comprehensive engineering guide and reference for the **HoverRunFW** firmware on hoverboard mainboards equipped with the **ArteryTek AT32F413RCT7** microcontroller. It explains the system architecture, how the direct RC PWM control operates, the root causes and permanent fixes for toolchain/flashing issues, and a step-by-step playbook for adapting new controllers, remotes, and motors in the future.

---

## 1. Hardware Architecture Overview

### Target Microcontroller
* **MCU**: ArteryTek **AT32F413RCT7**
* **Core**: ARM 32-bit Cortex-M4 with single-precision FPU
* **Clock Speed**: 72 MHz (configured via internal high-speed oscillator `SYSCLK_FREQ_72MHz_HSI`)
* **Flash Memory**: 256 KB
* **SRAM**: 64 KB (mapped at `0x20000000`)
* **Package**: LQFP64

### Pinout & Connector Reference

#### Left Sensor Cable (JST 4-Pin) - Primary Control Port
This connector originally attached to the left gyroscopic sensor board. It is repurposed for direct RC PWM input:

| Pin # | Wire Color (Typical) | MCU Pin | Function / Usage | Electrical Limits |
| :--- | :--- | :--- | :--- | :--- |
| **Pin 1** | Green / White | **PA2** | **Channel 1: Steering Signal** | **3.3 V max** (3.3V logic tolerant) |
| **Pin 2** | Blue / Yellow | **PA3** | **Channel 2: Throttle Signal** | **3.3 V max** (3.3V logic tolerant) |
| **Pin 3** | Black / Brown | **GND** | **System Ground** | 0 V Reference |
| **Pin 4** | Red | **VCC (+15V)**| **High-Voltage Pre-Regulated Rail** | **~14 V to 15 V (DO NOT CONNECT TO RECEIVER!)** |

> [!CAUTION]
> **NEVER connect the sensor cable's Red Wire (+15V) to your RC receiver!**
> Standard hobby receivers run on **5.0 V** or **3.3 V**. Connecting this 15V wire directly to a receiver will instantly burn out the receiver and can destroy the MCU's GPIO pins. Power your receiver from an external 5V step-down regulator (UBEC), a power bank, or a separate 5V source, and connect common Ground (`GND`).

#### Right Sensor Cable (JST 4-Pin) - Diagnostic & Telemetry UART
* **PB10**: USART3 TX (Output telemetry / scope diagnostics)
* **PB11**: USART3 RX (Input commands / ping / query)
* **GND**: System Ground
* **Red Wire**: +15 V (Do not connect)

#### Board SWD Programming Header
* **GND**: Connect to ST-Link Ground (Pin 1 on board)
* **SWDIO**: Connect to ST-Link SWDIO
* **SWCLK**: Connect to ST-Link SWCLK
* **3.3V**: **Leave disconnected!** The hoverboard board is self-powered from the battery.

#### Power Latching Circuit
The board contains a hardware power latch circuit:
* **Pin PA5 (`OFF_PIN`)**: The firmware drives `PA5` HIGH during initialization (`GPIO_WriteBit(OFF_PORT, OFF_PIN, 1)`) to maintain power to the board's internal voltage regulators.
* **Pin PA1 (`BUTTON_PIN`)**: Senses the physical momentary power button.
* **Why the Power Button Must Be Held While Flashing**: When an ST-Link resets or erases the MCU over SWD, the MCU pins go floating. `PA5` drops LOW, cutting main power instantly. Holding down the power button manually bridges the power FET, keeping the board energized throughout the erase and write cycle.

---

## 2. The Flashing & Unlocking Process: Issues Faced & How We Fixed Them

During setup and initial flashing of factory boards, several firmware and toolchain obstacles were identified and resolved:

### Issue 1: OpenOCD Missing from System PATH
* **Symptom**: `ERROR: OpenOCD not found. Install it, add it to PATH, or pass -OpenOcdPath.`
* **Root Cause**: `xpack-openocd-0.12.0-7` was downloaded into the user's `Downloads` folder but had not been registered in Windows environment variables.
* **Permanent Fix**: Updated [`flash.ps1`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/flash.ps1) with automatic fallback discovery. It automatically checks `$env:USERPROFILE\Downloads\xpack-openocd-*\...\bin\openocd.exe` and standard Program Files paths before erroring out.

### Issue 2: Flash Access Protection (FAP Level 1 / Write Lockout)
* **Symptom**: 
  ```text
  Error: Sector 0 is write protected
  Error: failed erasing sectors 0 to 10
  ```
  and `artery fap disable 0` produced:
  ```text
  Error: Timed out waiting for flash
  Error: Failed to erase user system data
  ```
* **Root Cause**:
  1. Factory hoverboard mainboards ship with hardware **Flash Access Protection (FAP / Readout Protection)** active (`FLASH_OBR` register `0x4002201C` bit 1 `RDPRT = 1`).
  2. The option bytes block at `0x1FFFF800` was in an erased state (`0xFFFFFFFF`). On the AT32, an erased option byte block fails the hardware complement check, which automatically locks all flash sectors.
  3. Upstream OpenOCD 0.12's `artery fap disable 0` command attempts to erase the User System Data (USD) using register offsets corresponding to newer AT32 chips (AT32F435), which times out on the AT32F413.
* **Permanent Fix**:
  Created a lightweight assembly unlock helper ([`Src/unlock_at32.s`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/unlock_at32.s)) that runs directly in target SRAM (`0x20000000`):
  1. Unlocks `FLASH->FCKEY` (`0x40022004`) with `0x45670123` and `0xCDEF89AB`.
  2. Unlocks `FLASH->OPTKEYR` (`0x40022008`) with `0x45670123` and `0xCDEF89AB`.
  3. Sets `CTRL_UOBWE` (bit 9), `CTRL_UOBERS` (bit 5), and `CTRL_STRT` (bit 6) in `FLASH->CTRL` (`0x40022010`) to initiate an option byte erase.
  4. Waits for the `BSY` flag in `FLASH->STS` (`0x4002200C`) to clear.
  5. Sets `CTRL_UOBPRGM` (bit 4) and writes `0x00A5` to `0x1FFFF800` (`UOPTB->RDPRT`).
  6. On reset, the hardware Option Byte Loader reads `0x5AA5`, clearing `RDPRT` and `OBERR` to 0. All 32 sectors become permanently writable.
  7. Automated compilation of this helper into `build/unlock_at32.bin` inside [`build.ps1`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/build.ps1), and updated [`unlock_target.cfg`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/unlock_target.cfg) to execute this sequence automatically.

### Issue 3: Sector-by-Sector Auto-Erase Failures
* **Symptom**: `flash write_image erase "build/hover.hex"` failed because the driver's per-sector protection check aborted the transaction.
* **Permanent Fix**: Updated [`stlink-command.cfg`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/stlink-command.cfg) to invoke `artery mass_erase 0` (which erases the full 256 KB flash in a single hardware cycle) followed by `flash write_image "build/hover.hex"` without the redundant per-sector `erase` flag.

---

## 3. Direct RC Remote Control: How It Works

### Signal Specifications
* **Protocol**: Standard hobby RC PWM (Pulse Width Modulation).
* **Pulse Frequency**: 50 Hz (1 frame every 20 ms).
* **Active Pulse Range**: 1000 µs to 2000 µs (Neutral at 1500 µs).

```
          +------+                                      +------+
          |      |                                      |      |
          |      |                                      |      |
  --------+      +--------------------------------------+      +-------
          <------>                                      <------>
          Pulse Width                                   Next Pulse
       (1000us - 2000us)                                 (20ms period)
```

### Firmware Architecture ([`Src/rc_pwm.c`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/rc_pwm.c))

1. **Microsecond Base Clock**:
   [`rc_pwm_init()`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/rc_pwm.c#L18) sets up timer `TMR2` with a prescaler:
   $$\text{Prescaler} = \frac{\text{SystemCoreClock}}{1\,000\,000} - 1 = \frac{72\,000\,000}{1\,000\,000} - 1 = 71$$
   This configures `TMR2->CNT` as a free-running counter where **1 tick = exactly 1 microsecond**.

2. **Edge Capture via EXTI**:
   * `EXTI2` (mapped to `PA2`) and `EXTI3` (mapped to `PA3`) trigger interrupts on both **rising and falling edges** (`EXTI_Trigger_Rising_Falling`).
   * When a rising edge is detected, `rise_time` records the current `TMR2->CNT`.
   * When a falling edge is detected, the pulse duration is calculated:
     $$\text{pulse} = \text{now} - \text{rise\_time}$$
     Unsigned 16-bit subtraction handles counter rollovers (`0xFFFF` -> `0x0000`) without timing glitches.
   * If $\text{pulse} \in [800\,\mu\text{s}, 2200\,\mu\text{s}]$, it is accepted and timestamps are updated.

3. **Deadband & Normalization**:
   The raw pulse is normalized into a signed range of $-1000$ to $+1000$:
   * **Center**: 1500 µs (`PWM_CENTER`)
   * **Deadband**: $\pm 25\,\mu\text{s}$ (`PWM_DEAD_BAND`). Pulses between $1475\,\mu\text{s}$ and $1525\,\mu\text{s}$ return `0` to prevent motor hum or creep when the transmitter sticks rest at center.
   * **Forward / Right**: $1525\,\mu\text{s}$ to $2000\,\mu\text{s} \longrightarrow 0$ to $+1000$.
   * **Reverse / Left**: $1000\,\mu\text{s}$ to $1475\,\mu\text{s} \longrightarrow -1000$ to $0$.

4. **Safety Failsafe & Loss-of-Signal**:
   [`rc_pwm_is_active()`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/rc_pwm.c#L129-L138) checks whether both channels have received valid pulses within the last $200\,\text{ms}$ (`PWM_TIMEOUT`):
   ```c
   if (rc_pwm_is_active()) {
       rc_pwm_update(&cmd1, &cmd2);
       update_timeout();
   } else {
       cmd1 = 0; // Force neutral steering
       cmd2 = 0; // Force neutral speed
   }
   ```
   If the transmitter loses signal, is powered off, or a cable is disconnected, the motors immediately command zero torque, preventing runaway conditions.

5. **Differential Steering Mixer ([`Src/main.c`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Src/main.c#L241-L255))**:
   * Raw commands pass through a low-pass filter (`FILTER = 0.1`) to reject noise:
     $$\text{speed} = \text{speed} \times (1 - \text{FILTER}) + \text{cmd2} \times \text{FILTER}$$
     $$\text{steer} = \text{steer} \times (1 - \text{FILTER}) + \text{cmd1} \times \text{FILTER}$$
   * Mixed for tank/differential drive:
     $$\text{speedR} = \text{CLAMP}(\text{speed} \times K_{\text{speed}} + \text{steer} \times K_{\text{steer}}, -1000, 1000)$$
     $$\text{speedL} = \text{CLAMP}(\text{speed} \times K_{\text{speed}} - \text{steer} \times K_{\text{steer}}, -1000, 1000)$$
   * Slew rate limiting ensures that motor outputs cannot change by more than $\pm 50$ units per 5 ms loop iteration, protecting the MOSFETs and reducing wheel spin on slick surfaces.

---

## 4. Adaptation Playbook for Future Projects

### Scenario A: Working with a New / Different Remote Control

1. **Reversing Throttle or Steering**:
   * **Option 1 (Transmitter)**: Reverse Channel 1 or Channel 2 on your RC transmitter's menu (recommended).
   * **Option 2 (Firmware)**: In [`Inc/config.h`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/config.h), invert the sign of the coefficients:
     ```c
     #define SPEED_COEFFICIENT -0.6 // Inverts forward / backward
     #define STEER_COEFFICIENT -0.5 // Inverts left / right
     ```

2. **Adjusting Transmitter Stick Center & Deadband**:
   If the vehicle creeps or hums when your joystick is centered:
   * Increase `PWM_DEAD_BAND` in [`Inc/config.h`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/config.h#L115) from `25` to `40` or `50`:
     ```c
     #define PWM_DEAD_BAND 40
     ```

3. **Adjusting Speed & Turning Sensitivity**:
   * `SPEED_COEFFICIENT`: Controls max forward/reverse speed (default `0.6`). Increase up to `1.0` or `1.2` for higher speed, or lower to `0.3` for slow precision robotics.
   * `STEER_COEFFICIENT`: Controls turn responsiveness (default `0.5`). Lower to `0.25` for smoother turns.

4. **Monitoring Raw Live Pulses over UART (PB10 / PB11)**:
   Connect a 3.3V USB-UART adapter (115200 baud) to the **Right Sensor Cable** (`PB10` TX, `PB11` RX, GND). Send the `status` command to receive real-time telemetry:
   * Scope Channel 5: Live steering pulse width in µs (e.g. `1500`)
   * Scope Channel 6: Live throttle pulse width in µs (e.g. `1500`)
   * Scope Channel 7: Signal validity (`1` = active, `0` = signal lost)

---

### Scenario B: Flashing a Brand-New Hoverboard Mainboard

When flashing a replacement or new V5.1 AT32 hoverboard mainboard for the first time:

1. **Wiring**:
   * Connect ST-Link **GND**, **SWDIO**, and **SWCLK** to the board header.
   * **Do NOT connect ST-Link 3.3V**.
   * Plug in the main battery (>36 V).

2. **Hold Power Button**:
   * Press and firmly **HOLD DOWN** the physical hoverboard power button (or solder a jumper across the two power switch pads).

3. **Check Connection**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Check
   ```
   *Expected output*: `SUCCESS: Target MCU detected and communicating!`

4. **Unlock Factory Protection (First Time Only)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Unlock
   ```
   *Expected output*: `SUCCESS: Chip unlocked and erased successfully!`

5. **Compile & Flash**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build.ps1
   powershell -ExecutionPolicy Bypass -File .\flash.ps1
   ```
   *Expected output*: `FLASH SUCCESSFUL! Firmware verified and running.`
   *Release the power button only after the flash completes.*

---

### Scenario C: Motor Commutation & Hall Sensor Mappings

If you change to different hoverboard hub motors (or the motor jerks, makes grinding noise, or draws high current without spinning smoothly), the motor phase wires and Hall sensor order might differ:

1. In [`Inc/config.h`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/config.h#L170-L171):
   ```c
   #define CONFIG_HALL_IDX_LEFT  0
   #define CONFIG_HALL_IDX_RIGHT 4
   ```
2. The index can be set from `0` to `5` (corresponding to the 6 possible permutations of 3 Hall sensor signals).
3. Test each index until the motor spins quietly, smoothly, and draws less than 1.0 A in free rotation.

---

### Scenario D: Battery Voltage Configuration

In [`Inc/config.h`](file:///c:/Users/ACM/Documents/bls%20robo/HoverRunFW-main/HoverRunFW-main/Inc/config.h#L38-L44):
```c
#define BAT_NUMBER_OF_CELLS 10 // Standard hoverboard battery (10s: 36V nominal, 42V peak)
#define BAT_LOW_LVL1 3.6       // Gentle beep threshold (36.0V for 10s)
#define BAT_LOW_LVL2 3.5       // Urgent warning beep threshold (35.0V for 10s)
#define BAT_LOW_DEAD 3.37      // Automatic poweroff threshold (33.7V for 10s)
```
* If running on a 7s battery (24V), change `BAT_NUMBER_OF_CELLS` to `7`.
* If running on a 12s battery, change `BAT_NUMBER_OF_CELLS` to `12`.
* `DC_CUR_LIMIT`: Set to `15` Amperes per motor by default (30 A total). Can be lowered to `10` for smaller batteries to prevent BMS overcurrent cutoffs.

---

## 5. Command Reference Cheat Sheet

| Task | Command Line |
| :--- | :--- |
| **Verify ST-Link & Target** | `powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Check` |
| **Compile Firmware** | `powershell -ExecutionPolicy Bypass -File .\build.ps1` |
| **Clean Build** | `powershell -ExecutionPolicy Bypass -File .\build.ps1 -Clean` |
| **Unlock Factory Board** | `powershell -ExecutionPolicy Bypass -File .\flash.ps1 -Unlock` |
| **Flash Firmware** | `powershell -ExecutionPolicy Bypass -File .\flash.ps1` |
