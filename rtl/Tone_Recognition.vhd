-- =============================================================================
-- Tone_Recognition : decodes the unit's audio output into a 2-bit result
--
-- iBinaryRec is the routed UUT output reduced to one bit by C_MainControl
-- (oBinaryRec). A rising edge on iFlagBinaryRec starts a recognition; while it
-- stays '1' the line is sampled on every iclk and the length of each '1' and
-- '0' run is counted. Result on oRecognized:
--   "00" disconnected - quiet line, no edge for QUIET_MS
--   "01" other        - a sound that is neither alert (e.g. a steady tone)
--   "10" Alert 1      - tone A gated on/off           (see rtl/Tone_Config.vhd)
--   "11" Alert 2      - tone A alternating with tone B (see rtl/Tone_Config.vhd)
-- oFlagRecognized = '1' once a result is on oRecognized; a later, different
-- result replaces it.
--
-- The tones and timing come from package tone_config (rtl/Tone_Config.vhd).
-- The values there are examples: set them for the unit you test.
--
-- Sampling a kHz signal at 50 MHz, one bad sample looks like an edge. Two
-- tolerance mechanisms make the recognition robust:
--   1. GRACE cycles. When the level changes, counting goes on for up to GRACE
--      more cycles. If the input returns to the old level inside them, the
--      cycles are added to the old level's counter (a glitch). If it does not,
--      the old run ends and the grace cycles are added to the new level's
--      counter, so run lengths stay exact.
--   2. CONFIRM cycles. A result is declared only after CONFIRM complete alert
--      cycles (2 * CONFIRM segments) have matched in a row, not after one.
--
-- Runs are classified as tone A / tone B half periods (+-TONE_TOL_PCT), a quiet
-- gap ('0' longer than 4 half periods of the lower tone) or other. Consecutive
-- runs of one class form a segment; each finished segment is checked against
-- both alert patterns.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

use work.tone_config.all;

entity Tone_Recognition is
  generic (
    CLK_HZ  : positive := 50_000_000;  -- iclk frequency
    GRACE   : positive := 30;          -- grace cycles
    CONFIRM : positive := 3            -- alert cycles before a result
  );
  port (
    iclk            : in  std_logic;                     -- 50 MHz system clock
    iReset          : in  std_logic;                     -- '1' = reset
    iBinaryRec      : in  std_logic;                     -- UUT output as one bit (oBinaryRec)
    iFlagBinaryRec  : in  std_logic;                     -- rising edge = start (oFlagBinaryRec)
    oRecognized     : out std_logic_vector(1 downto 0);  -- -> iRecognized
    oFlagRecognized : out std_logic                      -- '1' = oRecognized valid -> iFlagRecognized
  );
  attribute X_INTERFACE_INFO      : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO      of iReset : signal is "xilinx.com:signal:reset:1.0 iReset RST";
  attribute X_INTERFACE_PARAMETER of iReset : signal is "POLARITY ACTIVE_HIGH";
end entity;

architecture rtl of Tone_Recognition is

  function max(a, b : natural) return natural is
  begin
    if a > b then
      return a;
    end if;
    return b;
  end function;

  function min(a, b : natural) return natural is
  begin
    if a < b then
      return a;
    end if;
    return b;
  end function;

  -- lengths in iclk cycles
  constant HA     : natural := CLK_HZ / (2 * TONE_A_HZ);        -- tone A half period
  constant HB     : natural := CLK_HZ / (2 * TONE_B_HZ);        -- tone B half period
  constant GAP    : natural := 4 * max(HA, HB);                 -- '0' run longer = quiet gap
  constant STEADY : natural := CLK_HZ / 1000 * QUIET_MS;        -- no change this long = steady line
  constant A1_LEN : natural := CLK_HZ / 1000 * ALERT1_SEG_MS;
  constant A2_LEN : natural := CLK_HZ / 1000 * ALERT2_SEG_MS;
  constant A1_MIN : natural := A1_LEN / 100 * (100 - ALERT1_TOL_PCT);
  constant A1_MAX : natural := A1_LEN / 100 * (100 + ALERT1_TOL_PCT);
  constant A2_MIN : natural := A2_LEN / 100 * (100 - ALERT2_TOL_PCT);
  constant A2_MAX : natural := A2_LEN / 100 * (100 + ALERT2_TOL_PCT);
  constant NSEG   : natural := 2 * CONFIRM;

  type cls_t is (C_NONE, C_A, C_B, C_GAP, C_OTHER);

  function within(n, lo, hi : natural) return boolean is
  begin
    return n >= lo and n <= hi;
  end function;

  function sat(n : natural) return natural is
  begin
    if n > STEADY then
      return STEADY;
    end if;
    return n;
  end function;

  function classify(lvl : std_logic; len : natural) return cls_t is
  begin
    if within(len, HA * (100 - TONE_TOL_PCT) / 100, HA * (100 + TONE_TOL_PCT) / 100) then
      return C_A;
    elsif within(len, HB * (100 - TONE_TOL_PCT) / 100, HB * (100 + TONE_TOL_PCT) / 100) then
      return C_B;
    elsif lvl = '0' and len > GAP then
      return C_GAP;
    end if;
    return C_OTHER;
  end function;

  -- [1] run lengths with grace cycles
  signal level     : std_logic := '0';
  signal run_cnt   : natural range 0 to STEADY := 0;
  signal grace_cnt : natural range 0 to GRACE := 0;
  -- [2] segments and pattern counters
  signal seg_cls   : cls_t := C_NONE;
  signal seg_len   : natural range 0 to STEADY := 0;
  signal n_a1      : natural range 0 to NSEG := 0;
  signal n_a2      : natural range 0 to NSEG := 0;
  signal n_bad     : natural range 0 to NSEG := 0;
  signal rec       : std_logic_vector(1 downto 0) := "00";
  signal rec_valid : std_logic := '0';

begin

  -- ---- sanity checks on the values in Tone_Config -------------------------
  assert min(HA, HB) * (100 + TONE_TOL_PCT) < max(HA, HB) * (100 - TONE_TOL_PCT)
    report "Tone_Config: TONE_A_HZ and TONE_B_HZ are too close, their bands overlap"
    severity failure;
  assert ALERT2_SEG_MS * min(TONE_A_HZ, TONE_B_HZ) >= 10_000 and
         ALERT1_SEG_MS * TONE_A_HZ >= 10_000
    report "Tone_Config: an alert segment is shorter than 10 tone periods"
    severity failure;
  assert A2_MAX < A1_MIN or A1_MAX < A2_MIN
    report "Tone_Config: ALERT1_SEG_MS and ALERT2_SEG_MS are too close, their windows overlap"
    severity failure;
  assert GAP < A1_MIN and 10 * QUIET_MS > 15 * ALERT1_SEG_MS
    report "Tone_Config: QUIET_MS must be > 1.5 x ALERT1_SEG_MS"
    severity failure;
  assert HA > 4 * GRACE and HB > 4 * GRACE
    report "Tone_Config: a tone half period is too short for GRACE at this CLK_HZ"
    severity failure;

  oRecognized     <= rec;
  oFlagRecognized <= rec_valid;

  process (iclk)
    variable run_done : boolean;
    variable done_lvl : std_logic;
    variable done_len : natural range 0 to STEADY;
    variable cls      : cls_t;
    variable a1, a2   : boolean;

    procedure declare(code : std_logic_vector(1 downto 0)) is
    begin
      rec       <= code;
      rec_valid <= '1';
    end procedure;
  begin
    if rising_edge(iclk) then
      run_done := false;
      done_lvl := level;
      done_len := run_cnt;

      if iReset = '1' or iFlagBinaryRec = '0' then
        level     <= '0';
        run_cnt   <= 0;
        grace_cnt <= 0;
        seg_cls   <= C_NONE;
        seg_len   <= 0;
        n_a1      <= 0;
        n_a2      <= 0;
        n_bad     <= 0;
        rec       <= "00";
        rec_valid <= '0';
      else
        -- [1] count the current run; a change only counts after GRACE cycles
        if grace_cnt = 0 then
          if iBinaryRec = level then
            run_cnt <= sat(run_cnt + 1);
          else
            grace_cnt <= 1;
          end if;
        elsif iBinaryRec = level then            -- back inside the grace: a glitch
          run_cnt   <= sat(run_cnt + grace_cnt + 1);
          grace_cnt <= 0;
        elsif grace_cnt = GRACE then             -- still changed: a real edge
          run_done  := true;
          level     <= iBinaryRec;
          run_cnt   <= GRACE + 1;                -- grace cycles belong to the new run
          grace_cnt <= 0;
        else
          grace_cnt <= grace_cnt + 1;
        end if;

        -- no real edge for QUIET_MS: quiet line, or a constant level
        if run_cnt = STEADY then
          if level = '0' then
            declare("00");
          else
            declare("01");
          end if;
        end if;

        -- [2] runs -> segments -> alert patterns
        if run_done then
          cls := classify(done_lvl, done_len);
          if cls = seg_cls then
            seg_len <= sat(seg_len + done_len);
            if seg_len + done_len >= STEADY then
              declare("01");                     -- a constant tone is no alert
            end if;
          else
            if seg_cls /= C_NONE then
              a1 := (seg_cls = C_A or seg_cls = C_GAP) and within(seg_len, A1_MIN, A1_MAX);
              a2 := (seg_cls = C_A or seg_cls = C_B) and within(seg_len, A2_MIN, A2_MAX);

              if not a1 then
                n_a1 <= 0;
              elsif n_a1 < NSEG then
                n_a1 <= n_a1 + 1;
              end if;
              if a1 and n_a1 >= NSEG - 1 then
                declare("10");
              end if;

              if not a2 then
                n_a2 <= 0;
              elsif n_a2 < NSEG then
                n_a2 <= n_a2 + 1;
              end if;
              if a2 and n_a2 >= NSEG - 1 then
                declare("11");
              end if;

              if a1 or a2 then
                n_bad <= 0;
              elsif n_bad < NSEG then
                n_bad <= n_bad + 1;
              end if;
              if not (a1 or a2) and n_bad >= NSEG - 1 then
                declare("01");
              end if;
            end if;
            seg_cls <= cls;
            seg_len <= done_len;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
