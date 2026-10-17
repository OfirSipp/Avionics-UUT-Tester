-- =============================================================================
-- tb_ADC_DAC : ADC_LTC and DAC8043FP2 against bus-functional models
--
--   * LTC2327-16 model : BUSY after CNV, MSB on SDO when BUSY falls,
--                        next bit after every SCK rising edge (tDSDO 8 ns)
--   * DAC8043 model    : shifts SRI on CLK rising, loads on LD falling
--
-- Checks: ADC words through the serial chain, 200 kS/s, oDATA only changing
-- with a rising oFlag; DAC word and clock count, and a write made during a
-- transfer being sent next.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity tb_ADC_DAC is
end entity;

architecture sim of tb_ADC_DAC is

  constant TCLK : time := 20 ns;                       -- 50 MHz

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal adc_cnv, adc_sck, adc_busy, adc_sdo : std_logic := '0';
  signal adc_data  : std_logic_vector(15 downto 0);
  signal adc_flag  : std_logic;
  signal adc_value : std_logic_vector(15 downto 0) := x"8001";  -- "analog" input
  signal mon_err   : natural := 0;

  signal dac_word  : std_logic_vector(11 downto 0) := (others => '0');
  signal dac_flag  : std_logic := '0';
  signal dac_clk, dac_ld, dac_sdt : std_logic;
  signal dac_out   : std_logic_vector(11 downto 0) := (others => '0');
  signal dac_bits  : natural := 0;
  signal dac_loads : natural := 0;

begin

  clk <= not clk after TCLK / 2;

  adc : entity work.ADC_LTC
    port map (iclk => clk, iReset => rst, iSDO => adc_sdo, iBusy => adc_busy,
              oCNV => adc_cnv, oSCK => adc_sck, oDATA => adc_data, oFlag => adc_flag);

  dac : entity work.DAC8043FP2
    port map (iclk => clk, iReset => rst, iData => dac_word, iFlag => dac_flag,
              oCLK => dac_clk, oLD => dac_ld, oSDT => dac_sdt);

  -- LTC2327-16 bus-functional model -------------------------------------------
  adc_model : process
    variable word : std_logic_vector(15 downto 0);
  begin
    wait until rising_edge(adc_cnv);
    adc_busy <= '1' after 13 ns;
    word := adc_value;
    wait for 1.5 us;                                      -- conversion time
    adc_busy <= '0';
    adc_sdo  <= word(15);
    for i in 14 downto 0 loop
      wait until rising_edge(adc_sck);
      adc_sdo <= word(i) after 8 ns;                      -- tDSDO
    end loop;
  end process;

  -- oDATA may only change together with a rising oFlag
  adc_monitor : process (adc_data)
  begin
    if now > 0 ns and not rising_edge(adc_flag) then
      report "FAIL  oDATA changed without a rising oFlag" severity error;
      mon_err <= mon_err + 1;
    end if;
  end process;

  -- DAC8043 bus-functional model ----------------------------------------------
  dac_model : process (dac_clk, dac_ld)
    variable sh : std_logic_vector(11 downto 0) := (others => '0');
    variable n  : natural := 0;
  begin
    if rising_edge(dac_clk) then
      sh := sh(10 downto 0) & dac_sdt;
      n  := n + 1;
    end if;
    if falling_edge(dac_ld) then
      dac_out   <= sh;
      dac_bits  <= n;
      dac_loads <= dac_loads + 1;
      n         := 0;
    end if;
  end process;

  -- test sequence ---------------------------------------------------------------
  test : process
    variable errors : natural := 0;
    variable t0     : time;

    procedure check(ok : boolean; msg : string) is
    begin
      if ok then
        report "PASS  " & msg;
      else
        report "FAIL  " & msg severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure dac_write(word : std_logic_vector(11 downto 0)) is
    begin
      dac_word <= word;                                   -- oForDAC
      wait until rising_edge(clk);
      dac_flag <= '1';                                    -- oFlagForDAC rising edge
      wait until rising_edge(clk);
      dac_flag <= '0';
    end procedure;

  begin
    wait for 100 ns;
    rst <= '0';

    -- ADC_LTC
    wait until rising_edge(adc_flag);
    wait until rising_edge(adc_flag);
    check(adc_data = x"8001", "ADC_LTC reads 0x8001 through the serial chain");
    adc_value <= x"7FFE";
    wait until rising_edge(adc_flag);
    wait until rising_edge(adc_flag);
    check(adc_data = x"7FFE", "ADC_LTC reads 0x7FFE");

    t0 := now;
    for i in 1 to 20 loop
      wait until rising_edge(adc_flag);
    end loop;
    check(now - t0 = 100 us, "ADC_LTC samples at 200 kS/s (20 samples in 100 us)");
    check(mon_err = 0, "oDATA changes only with a rising oFlag");

    -- DAC8043FP2
    dac_write(x"A5C");
    wait until rising_edge(dac_ld);
    check(dac_out = x"A5C" and dac_bits = 12, "DAC8043FP2 sends 0xA5C in 12 clocks, then LD");

    dac_write(x"123");
    wait for 1 us;
    dac_write(x"456");                                    -- during the 0x123 transfer
    wait until rising_edge(dac_ld);
    check(dac_out = x"123", "first word of a back-to-back pair: 0x123");
    wait until rising_edge(dac_ld);
    check(dac_out = x"456" and dac_loads = 3, "word written during a transfer is sent next: 0x456");

    if errors = 0 then
      report "tb_ADC_DAC: ALL TESTS PASSED";
    else
      report "tb_ADC_DAC: " & integer'image(errors) & " FAILED" severity failure;
    end if;
    std.env.finish;
  end process;

end architecture;
