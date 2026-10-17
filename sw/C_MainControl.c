/*
 * C_MainControl.c - the test procedure
 *
 * Runs on the Zynq ARM (bare-metal standalone BSP) and implements the whole
 * test while controlling the relays, the ADC and DAC, the touch screen and
 * the MUX. The PL components do the timing-critical work:
 *   ADC_LTC          -> iFromADC / iFlagFromADC
 *   DAC8043FP2       <- oForDAC / oFlagForDAC
 *   Tone_Recognition <- oBinaryRec / oFlagBinaryRec, -> iRecognized / iFlagRecognized
 *
 * Every step: apply relays (and DAC level) -> route a UUT output to the ADC
 * through the MUX -> settle -> check -> show the result on the touch screen.
 */
#include <stdio.h>
#include "sleep.h"
#include "C_MainControl.h"
#include "nextion.h"

enum check {
    CHK_TONE,             /* Tone_Recognition result == lo                     */
    CHK_VOLT,             /* DC level of the routed output in [lo, hi] mV      */
    CHK_SENSE,            /* DIN5 via iForPullUp == lo (1 = open, 0 = GND)     */
    CHK_OPERATOR,         /* visual check, the technician answers on screen    */
};

typedef struct {
    const char *name;
    uint32_t    relays;
    int32_t     dac_mv;   /* DAC level, reaches the UUT only through DIN2_DAC */
    uint8_t     out;      /* UUT output routed to the ADC */
    uint8_t     check;
    int32_t     lo, hi;
    uint16_t    settle_ms;
} step_t;

/* EXAMPLE PROCEDURE. The steps, stimuli, expected results and limits below
 * only show how each kind of check is written; they are not the procedure of
 * any real unit. Replace them with the steps of your UUT's test
 * specification. */
static const step_t steps[] = {
  /* name                          relays                dac     out    check         lo              hi    settle */
    {"Self-test: DIN5 open",        0,                    0,      OUT_1, CHK_SENSE,    1,              0,     50},
    {"Self-test: DIN5 grounded",    DIN5_GND,             0,      OUT_1, CHK_SENSE,    0,              0,     50},
    {"Unpowered - output quiet",    0,                    0,      OUT_1, CHK_TONE,     REC_DISCONNECT, 0,    200},
    {"Powered - output quiet",      PWR_28V,              0,      OUT_1, CHK_TONE,     REC_DISCONNECT, 0,    500},
    {"DIN6 = +3 V -> OUT 2 level",  PWR_28V | DIN6_3V,    0,      OUT_2, CHK_VOLT,     2000,           4000, 300},
    {"DIN7 = +5 V -> OUT 3 level",  PWR_28V | DIN7_5V,    0,      OUT_3, CHK_VOLT,     4000,           6000, 300},
    {"DIN1 = +28 V -> Alert 1",     PWR_28V | DIN1_28V,   0,      OUT_1, CHK_TONE,     REC_ALERT1,     0,    200},
    {"DIN4 = +0.7 V -> Alert 2",    PWR_28V | DIN4_0V7,   0,      OUT_1, CHK_TONE,     REC_ALERT2,     0,    200},
    {"DIN2 = -2.5 V -> Alert 1",    PWR_28V | DIN2_DAC,   -2500,  OUT_1, CHK_TONE,     REC_ALERT1,     0,    200},
    {"AUX on - visual check",       PWR_28V | AUX_28V,    0,      OUT_4, CHK_OPERATOR, 0,              0,    300},
};
#define NSTEPS ((int)(sizeof steps / sizeof steps[0]))

static const char *const rec_name[] = {"DISCONNECTED", "OTHER", "ALERT 1", "ALERT 2"};

static void wait_ms(uint32_t ms)
{
    usleep(ms * 1000);
}

/* oRelayU13..U25 */
static void set_relays(uint32_t mask)
{
    wr(GPIO_RELAY_BASE + CH1, mask);
}

/* MUX: route a UUT output to the ADC */
static void set_mux(uint8_t out)
{
    wr(GPIO_MUX_BASE + CH1, MUX_EN | out);
}

/* oForDAC, then a rising edge on oFlagForDAC */
static void set_dac_mv(int32_t mv)
{
    int32_t code = mv * 4096 / DAC_FS_MV;

    wr(GPIO_DAC_BASE + CH1, (uint32_t)(code < 0 ? 0 : code > 4095 ? 4095 : code));
    wr(GPIO_DAC_BASE + CH2, 1);
    wr(GPIO_DAC_BASE + CH2, 0);
}

/* next sample: wait for a rising edge of iFlagFromADC, then read iFromADC */
static int16_t adc_read(void)
{
    while (rd(GPIO_ADC_BASE + CH2) & 1)
        ;
    while (!(rd(GPIO_ADC_BASE + CH2) & 1))
        ;
    return (int16_t)rd(GPIO_ADC_BASE + CH1);
}

/* mean of n samples, in mV */
static int32_t measure_mv(int n)
{
    int32_t sum = 0;

    for (int i = 0; i < n; i++)
        sum += ADC_MV(adc_read());
    return sum / n - ADC_OFS_MV;
}

/* Feed the routed output to Tone_Recognition, one bit (oBinaryRec) per ADC
 * sample, until it reports 'want' or timeout_ms passes. Returns the last
 * result (iRecognized), or -1 if there was none. */
static int recognize(int want, uint32_t timeout_ms)
{
    int bit = 0, rec = -1;

    wr(GPIO_RECTX_BASE + CH2, 0);                  /* oFlagBinaryRec low...   */
    wr(GPIO_RECTX_BASE + CH1, 0);
    wr(GPIO_RECTX_BASE + CH2, 1);                  /* ...rising edge: start   */

    for (uint32_t n = 0; n < timeout_ms * (FS_HZ / 1000); n++) {
        int32_t mv = ADC_MV(adc_read());
        if (mv > TONE_HI_MV)
            bit = 1;
        else if (mv < TONE_LO_MV)
            bit = 0;
        wr(GPIO_RECTX_BASE + CH1, (uint32_t)bit);

        if (rd(GPIO_RECRX_BASE + CH2) & 1) {       /* iFlagRecognized */
            rec = (int)(rd(GPIO_RECRX_BASE + CH1) & 3);
            if (rec == want)
                break;
        }
    }
    return rec;
}

static int wait_button(void)
{
    int id;
    while ((id = nx_poll_touch()) < 0)
        wait_ms(10);
    return id;
}

/* run one step; returns 1 = pass, writes the measurement text into meas */
static int run_step(const step_t *s, char *meas, size_t len)
{
    set_relays(s->relays);
    set_dac_mv(s->dac_mv);
    set_mux(s->out);
    wait_ms(s->settle_ms);

    switch (s->check) {
    case CHK_TONE: {
        int rec = recognize((int)s->lo, RECOGNIZE_TIMEOUT_MS);
        snprintf(meas, len, "%s", rec < 0 ? "no result" : rec_name[rec]);
        return rec == s->lo;
    }
    case CHK_VOLT: {
        int32_t mv = measure_mv(256);
        snprintf(meas, len, "%ld mV", (long)mv);
        return mv >= s->lo && mv <= s->hi;
    }
    case CHK_SENSE: {
        int open = (rd(GPIO_RELAY_BASE + CH2) & 1) != 0;   /* iForPullUp */
        snprintf(meas, len, "%s", open ? "open" : "grounded");
        return open == s->lo;
    }
    case CHK_OPERATOR: {
        nx_text("t1", "Indicator on?  OK / FAIL");
        int ok = wait_button() == NX_BTN_OK;
        snprintf(meas, len, "operator: %s", ok ? "OK" : "FAIL");
        return ok;
    }
    }
    return 0;
}

static void safe_state(void)
{
    set_relays(0);
    set_dac_mv(0);
    wr(GPIO_MUX_BASE + CH1, 0);
}

int main(void)
{
    char meas[48], line[64];

    for (;;) {
        safe_state();
        nx_cmd("page main");
        nx_color("t0", NX_WHITE);
        nx_text("t0", "Avionics UUT Tester");
        nx_text("t1", "Connect the UUT and press START");
        nx_text("t2", "");
        nx_progress(0);
        wait_button();

        int failed = 0;
        for (int i = 0; i < NSTEPS; i++) {
            const step_t *s = &steps[i];
            nx_text("t0", s->name);
            nx_text("t1", "testing...");
            nx_text("t2", "");

            int pass = run_step(s, meas, sizeof meas);
            failed += !pass;

            nx_text("t1", meas);
            nx_text("t2", pass ? "PASS" : "FAIL");
            nx_color("t2", pass ? NX_GREEN : NX_RED);
            nx_progress((i + 1) * 100 / NSTEPS);

            if (!pass) {                         /* technician: continue or abort */
                nx_text("t1", "FAIL - OK to continue, FAIL to abort");
                if (wait_button() != NX_BTN_OK)
                    break;
            }
            wait_ms(300);
        }

        safe_state();
        nx_text("t0", failed ? "UUT FAILED" : "UUT PASSED");
        nx_color("t0", failed ? NX_RED : NX_GREEN);
        snprintf(line, sizeof line, "%d of %d steps failed - press START", failed, NSTEPS);
        nx_text("t1", line);
        wait_button();
    }
}
