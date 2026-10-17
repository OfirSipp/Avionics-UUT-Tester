-- =============================================================================
-- Tone_Config : the alert tones to recognize. SET THESE FOR YOUR UNIT.
--
-- The values below are EXAMPLES. They are not the tones of the original unit,
-- which are not published. Before you use the design, set them to the
-- frequencies and timing of the unit you test. This file is the only place
-- they are defined: Tone_Recognition (RTL), Tone_Generator and the testbench
-- all read them from here, so simulation and hardware always agree.
--
-- The two alert patterns that are recognized:
--   Alert 1 : tone A for ALERT1_SEG_MS, silence for ALERT1_SEG_MS, repeating
--             (tone A gated on/off at 1000 / (2 * ALERT1_SEG_MS) Hz)
--   Alert 2 : tone A for ALERT2_SEG_MS, tone B for ALERT2_SEG_MS, repeating
--             (A and B alternating at 1000 / (2 * ALERT2_SEG_MS) Hz)
-- A quiet line reads as "disconnected"; any other sound reads as "other".
--
-- Rules the values must follow (checked by assertions in Tone_Recognition):
--   * tone A and tone B at least 25 % apart, so their +-10 % bands don't touch
--   * each alert segment at least 10 tone periods long
--   * ALERT1_SEG_MS and ALERT2_SEG_MS windows (+-TOL %) must not overlap
--   * QUIET_MS longer than 1.5 x ALERT1_SEG_MS
-- =============================================================================
package tone_config is

  -- ---- example values: replace with your unit's ---------------------------
  constant TONE_A_HZ     : positive := 2500;   -- tone A, Hz (both alerts)
  constant TONE_B_HZ     : positive := 1100;   -- tone B, Hz (Alert 2 only)
  constant ALERT1_SEG_MS : positive := 250;    -- Alert 1: tone A on / off, ms each
  constant ALERT2_SEG_MS : positive := 40;     -- Alert 2: tone A / tone B, ms each
  constant OTHER_HZ      : positive := 5000;   -- Tone_Generator only: a steady non-alert tone

  -- ---- recognition settings (usually left as they are) --------------------
  constant QUIET_MS      : positive := 1000;   -- no edge for this long = steady line
  constant TONE_TOL_PCT  : positive := 10;     -- tone half-period tolerance
  constant ALERT1_TOL_PCT: positive := 20;     -- Alert 1 segment length tolerance
  constant ALERT2_TOL_PCT: positive := 30;     -- Alert 2 segment length tolerance

end package;
