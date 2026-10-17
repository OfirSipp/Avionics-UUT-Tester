/*
 * C_MainControl.h - hardware map of C_MainControl
 *
 * C_MainControl reaches every PL block through AXI GPIO; the component's port
 * names are kept in the comments. Bare-metal, no BSP drivers: every
 * peripheral is a few memory-mapped registers.
 */
#ifndef C_MAINCONTROL_H
#define C_MAINCONTROL_H

#include <stdint.h>

/* AXI addresses, fixed in vivado/build.tcl */
#define GPIO_RELAY_BASE   0x41200000u   /* ch1 oRelayU13..U25          ch2 iForPullUp      */
#define GPIO_MUX_BASE     0x41210000u   /* ch1 MUX A0, A1, EN                              */
#define GPIO_ADC_BASE     0x41220000u   /* ch1 iFromADC (16 bit)       ch2 iFlagFromADC    */
#define GPIO_DAC_BASE     0x41230000u   /* ch1 oForDAC (12 bit)        ch2 oFlagForDAC     */
#define GPIO_RECTX_BASE   0x41240000u   /* ch1 oBinaryRec              ch2 oFlagBinaryRec  */
#define GPIO_RECRX_BASE   0x41250000u   /* ch1 iRecognized (2 bit)     ch2 iFlagRecognized */
#define UART_SCREEN_BASE  0x40600000u   /* Nextion, 9600 8N1: oRxScreen / iTxScreen        */

#define CH1  0x0u                       /* AXI GPIO channel 1 data */
#define CH2  0x8u                       /* AXI GPIO channel 2 data */

/* MAX4534 MUX: the four UUT outputs on NO1..NO4 */
enum uut_out { OUT_1, OUT_2, OUT_3, OUT_4 };
#define MUX_EN       (1u << 2)

/* oRecognized of Tone_Recognition */
enum rec { REC_DISCONNECT, REC_OTHER, REC_ALERT1, REC_ALERT2 };

#define FS_HZ        200000u                                /* ADC_LTC sample rate */
#define ADC_MV(code) ((int32_t)(int16_t)(code) * 5 / 16)    /* 312.5 uV/LSB, +-10.24 V */

/* Calibration knobs: measure on the bench and adjust */
#define DAC_FS_MV    (-10000)  /* DAC8043 unipolar: Vout = -Vref * code / 4096, Vref = 10 V */
#define ADC_OFS_MV   0         /* ADC chain offset (MUX + LT1468 buffer)                   */
#define TONE_HI_MV   500       /* oBinaryRec goes '1' above this level...                  */
#define TONE_LO_MV   250       /* ...and back to '0' below this one (hysteresis)           */

/* ---- stimulus lines ----------------------------------------------------
 * Bit n of the relay word drives relay U(13+n) through IOn. Relay pairs
 * are a 2-level selector: the second relay connects the UUT line, the first
 * picks its source. Both off = line open. See docs/interface_board.md.
 * Map DIN1..DIN7 and AUX to your unit's connector in your own wiring.
 */
#define U(n)         (1u << ((n) - 13))

#define PWR_28V      (U(13))           /* UUT +28 V power                   */
#define AUX_28V      (U(14))           /* AUX  = +28 V                      */
#define DIN1_0V7     (U(16))           /* DIN1 = +0.7 V                     */
#define DIN1_28V     (U(15) | U(16))   /* DIN1 = +28 V                      */
#define DIN2_28V     (U(17))           /* DIN2 = +28 V                      */
#define DIN2_DAC     (U(18))           /* DIN2 = analog level from the DAC  */
#define DIN3_0V7     (U(19))           /* DIN3 = +0.7 V                     */
#define DIN4_0V7     (U(21))           /* DIN4 = +0.7 V                     */
#define DIN4_28V     (U(20) | U(21))   /* DIN4 = +28 V                      */
#define DIN5_GND     (U(22))           /* DIN5 = GND (read back: iForPullUp) */
#define DIN6_RETURN  0u                /* DIN6 = its return line            */
#define DIN6_0V7     (U(24))           /* DIN6 = +0.7 V                     */
#define DIN6_3V      (U(23) | U(24))   /* DIN6 = +3 V                       */
#define DIN7_5V      (U(25))           /* DIN7 = +5 V                       */

/* Tone_Recognition needs CONFIRM (3) full alert cycles before it answers:
 * keep this above 3 cycles of your slowest alert (see rtl/Tone_Config.vhd). */
#define RECOGNIZE_TIMEOUT_MS  5000u

/* ---- register access ---------------------------------------------------- */
static inline uint32_t rd(uint32_t addr)
{
    return *(volatile uint32_t *)(uintptr_t)addr;
}

static inline void wr(uint32_t addr, uint32_t val)
{
    *(volatile uint32_t *)(uintptr_t)addr = val;
}

/* ---- AXI UART Lite ------------------------------------------------------ */
#define UL_RX        0x0u
#define UL_TX        0x4u
#define UL_STAT      0x8u
#define UL_RX_VALID  (1u << 0)
#define UL_TX_FULL   (1u << 3)

static inline void uart_putc(uint32_t base, char c)
{
    while (rd(base + UL_STAT) & UL_TX_FULL)
        ;
    wr(base + UL_TX, (uint8_t)c);
}

static inline void uart_puts(uint32_t base, const char *s)
{
    while (*s)
        uart_putc(base, *s++);
}

static inline int uart_getc(uint32_t base)        /* -1 if nothing received */
{
    return (rd(base + UL_STAT) & UL_RX_VALID) ? (int)(rd(base + UL_RX) & 0xFFu) : -1;
}

#endif
