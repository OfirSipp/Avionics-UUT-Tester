-- =============================================================================
-- Tone_Generator : emulates the unit's audio output, for developing and
-- testing Tone_Recognition
--
-- Two switches select the signal, which leaves as a clean square wave. The
-- tones and timing come from package tone_config (rtl/Tone_Config.vhd):
--   "00" quiet line
--   "01" a steady OTHER_HZ tone - not an alert
--   "10" Alert 1 - tone A for ALERT1_SEG_MS, silence for ALERT1_SEG_MS
--   "11" Alert 2 - tone A for ALERT2_SEG_MS, tone B for ALERT2_SEG_MS
-- Synthesizable: on the Arty Z7-20 iSel can be SW1:SW0 and oTone a header pin,
-- to check the recognizer on the bench with a scope. Used by tb_Tone_Recognition.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

use work.tone_config.all;

entity Tone_Generator is
  generic (
    CLK_HZ : positive := 50_000_000
  );
  port (
    iclk  : in  std_logic;
    iSel  : in  std_logic_vector(1 downto 0);
    oTone : out std_logic
  );
end entity;

architecture rtl of Tone_Generator is
  constant HA : natural := CLK_HZ / (2 * TONE_A_HZ);   -- half periods in iclk cycles
  constant HB : natural := CLK_HZ / (2 * TONE_B_HZ);
  constant HO : natural := CLK_HZ / (2 * OTHER_HZ);
  -- segment lengths in half periods
  constant N_A1 : natural := 2 * ALERT1_SEG_MS * TONE_A_HZ / 1000;
  constant N_A2 : natural := 2 * ALERT2_SEG_MS * TONE_A_HZ / 1000;
  constant N_B2 : natural := 2 * ALERT2_SEG_MS * TONE_B_HZ / 1000;

  function max3(a, b, c : natural) return natural is
    variable m : natural := a;
  begin
    if b > m then m := b; end if;
    if c > m then m := c; end if;
    return m;
  end function;

  signal sel_d  : std_logic_vector(1 downto 0) := "00";
  signal phase  : std_logic := '0';            -- '0' first part of the pattern, '1' second
  signal cnt    : natural range 0 to max3(HA, HB, HO) := 0;
  signal halves : natural range 0 to max3(N_A1, N_A2, N_B2) := 0;
  signal sq     : std_logic := '1';
begin

  process (iclk)
    variable half  : natural;                  -- half period of the current part
    variable nhalf : natural;                  -- its length in half periods
  begin
    if rising_edge(iclk) then
      case iSel is
        when "01"   => half := HO; nhalf := 2;
        when "10"   => half := HA; nhalf := N_A1;
        when "11"   =>
          if phase = '0' then
            half := HA; nhalf := N_A2;
          else
            half := HB; nhalf := N_B2;
          end if;
        when others => half := HA; nhalf := 2;
      end case;

      sel_d <= iSel;
      if iSel /= sel_d then                    -- new selection: start clean
        cnt    <= 0;
        halves <= 0;
        phase  <= '0';
        sq     <= '1';
      elsif cnt = half - 1 then
        cnt <= 0;
        sq  <= not sq;
        if halves = nhalf - 1 then
          halves <= 0;
          phase  <= not phase;
        else
          halves <= halves + 1;
        end if;
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  oTone <= '0' when iSel = "00" or (iSel = "10" and phase = '1') else sq;

end architecture;
