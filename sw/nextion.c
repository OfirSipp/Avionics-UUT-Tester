/*
 * nextion.c - Nextion touch screen over AXI UART Lite (see nextion.h)
 */
#include <stdio.h>
#include "C_MainControl.h"
#include "nextion.h"

void nx_cmd(const char *cmd)
{
    uart_puts(UART_SCREEN_BASE, cmd);
    for (int i = 0; i < 3; i++)
        uart_putc(UART_SCREEN_BASE, (char)0xFF);
}

void nx_text(const char *obj, const char *text)
{
    char buf[96];
    snprintf(buf, sizeof buf, "%s.txt=\"%s\"", obj, text);
    nx_cmd(buf);
}

void nx_color(const char *obj, uint16_t rgb565)
{
    char buf[32];
    snprintf(buf, sizeof buf, "%s.pco=%u", obj, rgb565);
    nx_cmd(buf);
}

void nx_progress(int percent)
{
    char buf[16];
    snprintf(buf, sizeof buf, "j0.val=%d", percent);
    nx_cmd(buf);
}

/* Touch event frame: 0x65 page comp event FF FF FF. Bytes are consumed as
 * they arrive; anything that does not fit the frame restarts the parser. */
int nx_poll_touch(void)
{
    static uint8_t frame[7];
    static int     len;
    int c;

    while ((c = uart_getc(UART_SCREEN_BASE)) >= 0) {
        if (len == 0 && c != 0x65)
            continue;
        frame[len++] = (uint8_t)c;
        if (len >= 5 && c != 0xFF) {       /* terminator corrupted */
            len = 0;
            continue;
        }
        if (len == 7) {
            len = 0;
            if (frame[3] == 1)             /* 1 = press, 0 = release */
                return frame[2];
        }
    }
    return -1;
}
