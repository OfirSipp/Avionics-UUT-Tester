/*
 * nextion.h - minimal driver for the Nextion NX4827T043 touch screen
 *
 * Protocol: ASCII instructions terminated by 0xFF 0xFF 0xFF.
 * Touch events arrive as 0x65 <page> <component> <event> 0xFF 0xFF 0xFF.
 *
 * Expected HMI layout (page "main"):
 *   t0  title / step name      t1  instruction or measured value
 *   t2  verdict (PASS / FAIL)  j0  progress bar
 *   b0  OK / START  (id 4)     b1  FAIL (id 5)
 */
#ifndef NEXTION_H
#define NEXTION_H

#include <stdint.h>

#define NX_BTN_OK    4
#define NX_BTN_FAIL  5

#define NX_GREEN     2016u   /* RGB565 */
#define NX_RED       63488u
#define NX_WHITE     65535u

void nx_cmd(const char *cmd);
void nx_text(const char *obj, const char *text);
void nx_color(const char *obj, uint16_t rgb565);
void nx_progress(int percent);
int  nx_poll_touch(void);              /* component id of a press, or -1 */

#endif
