/**
 * @file rc_pwm.h
 * @brief Dual-channel RC PWM interface for AT32F413 Hoverboard Controller
 * @author Mithlaj MT (@mithlajmt)
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize TMR2 and EXTI for two RC PWM inputs on the left sensor cable:
 *        Channel 1 (Steering) -> PA2 (L_TX pin)
 *        Channel 2 (Throttle) -> PA3 (L_RX pin)
 */
void rc_pwm_init(void);

/**
 * @brief Convert captured pulse widths to normalized -1000..+1000 steer & speed values.
 *        PWM_MIN/PWM_CENTER/PWM_MAX set the input calibration; values outside
 *        the configured endpoints saturate at -1000 or +1000.
 * @param steer_out Pointer to receive normalized steering value (-1000 to +1000)
 * @param speed_out Pointer to receive normalized speed value (-1000 to +1000)
 */
void rc_pwm_update(int *steer_out, int *speed_out);

/**
 * @brief Check that both channels have recent valid pulses within PWM_TIMEOUT.
 * @return true if both RC channels are active and valid, false otherwise.
 */
bool rc_pwm_is_active(void);

/**
 * @brief Get the latest raw pulse width for Steering channel in microseconds.
 */
uint16_t rc_pwm_get_raw_steer(void);

/**
 * @brief Get the latest raw pulse width for Speed channel in microseconds.
 */
uint16_t rc_pwm_get_raw_speed(void);

#ifdef __cplusplus
}
#endif
