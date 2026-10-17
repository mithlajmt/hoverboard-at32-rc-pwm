#include "rc_pwm.h"
#include "at32f4xx.h"
#include "defines.h"

extern uint32_t millis(void);

static volatile uint16_t rise_time_ch1 = 0;
static volatile uint16_t rise_time_ch2 = 0;
static volatile bool ch1_is_high = false;
static volatile bool ch2_is_high = false;

static volatile uint16_t raw_pulse_ch1 = PWM_CENTER; // Steering (PA2)
static volatile uint16_t raw_pulse_ch2 = PWM_CENTER; // Speed (PA3)

static volatile uint32_t last_pulse_time_ch1 = 0;
static volatile uint32_t last_pulse_time_ch2 = 0;

void rc_pwm_init(void)
{
  GPIO_InitType GPIO_InitStruct = {0};
  EXTI_InitType EXTI_InitStruct = {0};
  NVIC_InitType NVIC_InitStruct = {0};
  TMR_TimerBaseInitType TMR_TimeBaseInitStruct = {0};

  /* Enable clocks for GPIOA, AFIO, and TMR2 */
  RCC_APB2PeriphClockCmd(RCC_APB2PERIPH_GPIOA | RCC_APB2PERIPH_AFIO, ENABLE);
  RCC_APB1PeriphClockCmd(RCC_APB1PERIPH_TMR2, ENABLE);

  /* Configure TMR2 as a 1 MHz free-running microsecond counter (1 tick = 1 us) */
  TMR_TimeBaseStructInit(&TMR_TimeBaseInitStruct);
  TMR_TimeBaseInitStruct.TMR_DIV = (SystemCoreClock / 1000000) - 1;
  TMR_TimeBaseInitStruct.TMR_CounterMode = TMR_CounterDIR_Up;
  TMR_TimeBaseInitStruct.TMR_Period = 0xFFFF;
  TMR_TimeBaseInitStruct.TMR_ClockDivision = TMR_CKD_DIV1;
  TMR_TimeBaseInitStruct.TMR_RepetitionCounter = 0;
  TMR_TimeBaseInit(TMR2, &TMR_TimeBaseInitStruct);
  
  /* Force an update event to immediately reload prescaler value */
  TMR_GenerateEvent(TMR2, TMR_EventSource_Update);
  TMR_ClearFlag(TMR2, TMR_FLAG_Update);
  TMR_Cmd(TMR2, ENABLE);

  /* Configure PA2 (L_TX / Ch1) and PA3 (L_RX / Ch2) as inputs with pull-down */
  GPIO_InitStruct.GPIO_Pins = GPIO_Pins_2 | GPIO_Pins_3;
  GPIO_InitStruct.GPIO_Mode = GPIO_Mode_IN_PD;
  GPIO_InitStruct.GPIO_MaxSpeed = GPIO_MaxSpeed_50MHz;
  GPIO_Init(GPIOA, &GPIO_InitStruct);

  /* Connect EXTI Lines to GPIOA Pins */
  GPIO_EXTILineConfig(GPIO_PortSourceGPIOA, GPIO_PinsSource2);
  GPIO_EXTILineConfig(GPIO_PortSourceGPIOA, GPIO_PinsSource3);

  /* Configure EXTI lines for rising and falling edges */
  EXTI_InitStruct.EXTI_Line = EXTI_Line2 | EXTI_Line3;
  EXTI_InitStruct.EXTI_Mode = EXTI_Mode_Interrupt;
  EXTI_InitStruct.EXTI_Trigger = EXTI_Trigger_Rising_Falling;
  EXTI_InitStruct.EXTI_LineEnable = ENABLE;
  EXTI_Init(&EXTI_InitStruct);

  /* Configure NVIC for EXTI2 (Channel 1 - Steer) */
  NVIC_InitStruct.NVIC_IRQChannel = EXTI2_IRQn;
  NVIC_InitStruct.NVIC_IRQChannelPreemptionPriority = 1;
  NVIC_InitStruct.NVIC_IRQChannelSubPriority = 2;
  NVIC_InitStruct.NVIC_IRQChannelCmd = ENABLE;
  NVIC_Init(&NVIC_InitStruct);

  /* Configure NVIC for EXTI3 (Channel 2 - Speed) */
  NVIC_InitStruct.NVIC_IRQChannel = EXTI3_IRQn;
  NVIC_InitStruct.NVIC_IRQChannelPreemptionPriority = 1;
  NVIC_InitStruct.NVIC_IRQChannelSubPriority = 3;
  NVIC_InitStruct.NVIC_IRQChannelCmd = ENABLE;
  NVIC_Init(&NVIC_InitStruct);
}

void EXTI2_IRQHandler(void)
{
  if (EXTI_GetIntStatus(EXTI_Line2) != RESET)
  {
    uint16_t now = (uint16_t)TMR2->CNT;
    if (GPIO_ReadInputDataBit(GPIOA, GPIO_Pins_2))
    {
      rise_time_ch1 = now;
      ch1_is_high = true;
    }
    else
    {
      if (ch1_is_high)
      {
        uint16_t pulse = (uint16_t)(now - rise_time_ch1);
        if (pulse >= PWM_VALID_MIN && pulse <= PWM_VALID_MAX)
        {
          raw_pulse_ch1 = pulse;
          last_pulse_time_ch1 = millis();
        }
        ch1_is_high = false;
      }
    }
    EXTI_ClearIntPendingBit(EXTI_Line2);
  }
}

void EXTI3_IRQHandler(void)
{
  if (EXTI_GetIntStatus(EXTI_Line3) != RESET)
  {
    uint16_t now = (uint16_t)TMR2->CNT;
    if (GPIO_ReadInputDataBit(GPIOA, GPIO_Pins_3))
    {
      rise_time_ch2 = now;
      ch2_is_high = true;
    }
    else
    {
      if (ch2_is_high)
      {
        uint16_t pulse = (uint16_t)(now - rise_time_ch2);
        if (pulse >= PWM_VALID_MIN && pulse <= PWM_VALID_MAX)
        {
          raw_pulse_ch2 = pulse;
          last_pulse_time_ch2 = millis();
        }
        ch2_is_high = false;
      }
    }
    EXTI_ClearIntPendingBit(EXTI_Line3);
  }
}

bool rc_pwm_is_active(void)
{
  uint32_t now = millis();
  if (last_pulse_time_ch1 == 0 || last_pulse_time_ch2 == 0)
  {
    return false;
  }
  return ((now - last_pulse_time_ch1) < PWM_TIMEOUT) &&
         ((now - last_pulse_time_ch2) < PWM_TIMEOUT);
}

static int map_pwm_channel(uint16_t pulse)
{
  int output = 0;
  if (pulse >= (PWM_CENTER - PWM_DEAD_BAND) && pulse <= (PWM_CENTER + PWM_DEAD_BAND))
  {
    output = 0;
  }
  else if (pulse > (PWM_CENTER + PWM_DEAD_BAND))
  {
    int32_t span = PWM_MAX - (PWM_CENTER + PWM_DEAD_BAND);
    if (span > 0)
    {
      output = (int32_t)(pulse - (PWM_CENTER + PWM_DEAD_BAND)) * 1000 / span;
    }
  }
  else if (pulse < (PWM_CENTER - PWM_DEAD_BAND))
  {
    int32_t span = (PWM_CENTER - PWM_DEAD_BAND) - PWM_MIN;
    if (span > 0)
    {
      output = (int32_t)(pulse - (PWM_CENTER - PWM_DEAD_BAND)) * 1000 / span;
    }
  }

  return CLAMP(output, -1000, 1000);
}

void rc_pwm_update(int *steer_out, int *speed_out)
{
  if (steer_out)
  {
    *steer_out = map_pwm_channel(raw_pulse_ch1);
  }
  if (speed_out)
  {
    *speed_out = map_pwm_channel(raw_pulse_ch2);
  }
}

uint16_t rc_pwm_get_raw_steer(void)
{
  return raw_pulse_ch1;
}

uint16_t rc_pwm_get_raw_speed(void)
{
  return raw_pulse_ch2;
}
