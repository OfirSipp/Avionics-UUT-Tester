-- =============================================================================
-- tb_Tone_Recognition : Tone_Generator -> Tone_Recognition, all four results
--
-- The generator plays each signal, Tone_Recognition is restarted
-- (iFlagBinaryRec 0 -> 1) and must report the matching code. Short glitches
-- (1..29 cycles, below GRACE) are injected on the line every 5.3 ms throughout.
--
-- Checks per phase: the result, and when it came. Alert 1 and Alert 2 must not
-- be declared before CONFIRM full cycles; quiet and steady lines after QUIET_MS.
-- The result must then hold for HOLD while the signal goes on.
-- Every expected time is computed from rtl/Tone_Config.vhd, so the testbench
-- follows whatever tones you configure there.
--
-- iclk runs at 5 MHz instead of 50 MHz: the signals and timings in seconds
-- are the same, the simulator has 10x fewer cycles to run.
-- Generic G_GRACE (default 30) lets you rerun with the grace cycles disabled:
--   ghdl --elab-run --std=08 tb_Tone_Recognition -gG_GRACE=1
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

use work.tone_config.all;

entity tb_Tone_Recognition is
  generic (
    G_GRACE : positive := 30
  );
end entity;

architecture sim of tb_Tone_Recognition is

  constant CLK_HZ  : positive := 5_000_000;
  constant TCLK    : time     := 1 sec / CLK_HZ;
  constant HOLD    : time     := 500 ms;
  constant CONFIRM : positive := 3;

  -- expected time to a result, ms
  constant T_QUIET : natural := QUIET_MS;
  constant T_A1    : natural := 2 * CONFIRM * ALERT1_SEG_MS;
  constant T_A2    : natural := 2 * CONFIRM * ALERT2_SEG_MS;

  type phase_t is record
    sel    : std_logic_vector(1 downto 0);     -- generator signal = expected code
    name   : string(1 to 7);
    t_ms   : natural;                          -- expected time to the result
  end record;
  type phases_t is array (natural range <>) of phase_t;

  constant PHASES : phases_t := (
    ("00", "quiet  ", T_QUIET),
    ("10", "alert 1", T_A1),
    ("11", "alert 2", T_A2),
    ("01", "other  ", T_QUIET),
    ("00", "quiet  ", T_QUIET));

  signal clk    : std_logic := '0';
  signal sel    : std_logic_vector(1 downto 0) := "00";
  signal tone   : std_logic;
  signal glitch : std_logic := '0';
  signal line   : std_logic;
  signal flag   : std_logic := '0';
  signal rec    : std_logic_vector(1 downto 0);
  signal valid  : std_logic;

begin

  clk  <= not clk after TCLK / 2;
  line <= tone xor glitch;

  gen : entity work.Tone_Generator
    generic map (CLK_HZ => CLK_HZ)
    port map (iclk => clk, iSel => sel, oTone => tone);

  dut : entity work.Tone_Recognition
    generic map (CLK_HZ => CLK_HZ, GRACE => G_GRACE, CONFIRM => CONFIRM)
    port map (
      iclk => clk, iReset => '0',
      iBinaryRec => line, iFlagBinaryRec => flag,
      oRecognized => rec, oFlagRecognized => valid);

  -- a glitch of 1..29 cycles every 5.3 ms, off the clock edges
  glitcher : process
  begin
    wait for TCLK / 4;
    for k in 0 to integer'high loop
      wait for 5.3 ms;
      glitch <= '1';
      wait for (1 + k mod 29) * TCLK;
      glitch <= '0';
    end loop;
  end process;

  test : process
    variable t0     : time;
    variable t_ms   : natural;
    variable lo, hi : natural;
    variable ok     : boolean;
    variable errors : natural := 0;
  begin
    report "tones: A " & integer'image(TONE_A_HZ) & " Hz, B " & integer'image(TONE_B_HZ) &
           " Hz, Alert 1 segments " & integer'image(ALERT1_SEG_MS) & " ms, Alert 2 segments " &
           integer'image(ALERT2_SEG_MS) & " ms, grace " & integer'image(G_GRACE) & " cycles";
    wait for 1 us;
    for i in PHASES'range loop
      lo := PHASES(i).t_ms * 95 / 100;           -- not earlier than CONFIRM cycles
      hi := PHASES(i).t_ms * 110 / 100 + 20;
      sel  <= PHASES(i).sel;
      flag <= '0';                                -- restart recognition
      wait for 2 * TCLK;
      flag <= '1';
      t0 := now;
      wait until valid = '1' for hi * 1 ms;
      t_ms := (now - t0) / 1 ms;
      ok   := valid = '1' and rec = PHASES(i).sel and t_ms >= lo;
      wait for HOLD;
      ok   := ok and valid = '1' and rec = PHASES(i).sel;

      if ok then
        report "PASS  " & PHASES(i).name & " -> " & to_string(rec) &
               " after " & integer'image(t_ms) & " ms, held " & integer'image(HOLD / 1 ms) & " ms";
      else
        report "FAIL  " & PHASES(i).name & " -> " & to_string(rec) & " valid=" &
               std_logic'image(valid) & " after " & integer'image(t_ms) & " ms (expected " &
               integer'image(lo) & ".." & integer'image(hi) & " ms)"
          severity error;
        errors := errors + 1;
      end if;
    end loop;

    if errors = 0 then
      report "tb_Tone_Recognition: ALL TESTS PASSED";
    else
      report "tb_Tone_Recognition: " & integer'image(errors) & " FAILED" severity failure;
    end if;
    std.env.finish;
  end process;

end architecture;
