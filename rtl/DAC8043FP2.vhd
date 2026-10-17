-- =============================================================================
-- DAC8043FP2 : DAC8043 12-bit serial DAC loader
--
-- A rising edge on iFlag (oFlagForDAC of C_MainControl) means iData holds a
-- new 12-bit word. The component then drives the DAC8043:
--   oSDT : serial data (DAC pin SRI), MSB first, taken by the DAC on CLK rising
--   oCLK : 12 pulses shift the word into the DAC input register
--   oLD  : active-low pulse copies the input register to the DAC register,
--          so the analog output changes once, glitch-free, with the full word
--
-- A rising edge that arrives during a transfer is remembered; the next
-- transfer then sends whatever iData holds at that time (last write wins).
--
-- Each phase lasts HALF clocks (default 10 -> 200 ns @ 50 MHz), comfortably
-- above the DAC8043 data-setup, clock-width and LD-width minimums.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity DAC8043FP2 is
  generic (
    HALF : positive := 10
  );
  port (
    iclk   : in  std_logic;                      -- 50 MHz system clock
    iReset : in  std_logic;                      -- '1' = reset (project Reset button)
    iData  : in  std_logic_vector(11 downto 0);  -- word from oForDAC
    iFlag  : in  std_logic;                      -- rising edge = iData ready (oFlagForDAC)
    oCLK   : out std_logic;                      -- DAC8043 CLK (IO30)
    oLD    : out std_logic;                      -- DAC8043 LD  (IO31), active low
    oSDT   : out std_logic                       -- DAC8043 SRI (IO29)
  );
  attribute X_INTERFACE_INFO      : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO      of iReset : signal is "xilinx.com:signal:reset:1.0 iReset RST";
  attribute X_INTERFACE_PARAMETER of iReset : signal is "POLARITY ACTIVE_HIGH";
end entity;

architecture rtl of DAC8043FP2 is
  type state_t is (IDLE, CLK_LO, CLK_HI, LOAD);
  signal state   : state_t := IDLE;
  signal tmr     : natural range 0 to HALF - 1 := 0;
  signal bit_cnt : natural range 0 to 11 := 0;
  signal shreg   : std_logic_vector(11 downto 0) := (others => '0');
  signal flag_d  : std_logic := '0';
  signal pending : std_logic := '0';
  signal clk_r   : std_logic := '0';
  signal ld_r    : std_logic := '1';
begin

  oCLK <= clk_r;
  oSDT <= shreg(11);
  oLD  <= ld_r;

  process (iclk)
  begin
    if rising_edge(iclk) then
      flag_d <= iFlag;

      if iReset = '1' then
        state   <= IDLE;
        pending <= '0';
        clk_r   <= '0';
        ld_r    <= '1';
      else
        if iFlag = '1' and flag_d = '0' then
          pending <= '1';
        end if;

        case state is
          when IDLE =>
            if pending = '1' then
              pending <= '0';
              shreg   <= iData;
              bit_cnt <= 11;
              tmr     <= 0;
              state   <= CLK_LO;
            end if;

          when CLK_LO =>                         -- SRI settles while CLK is low
            if tmr = HALF - 1 then
              tmr   <= 0;
              clk_r <= '1';
              state <= CLK_HI;
            else
              tmr <= tmr + 1;
            end if;

          when CLK_HI =>
            if tmr = HALF - 1 then
              tmr   <= 0;
              clk_r <= '0';
              if bit_cnt = 0 then
                ld_r  <= '0';
                state <= LOAD;
              else
                bit_cnt <= bit_cnt - 1;
                shreg   <= shreg(10 downto 0) & '0';
                state   <= CLK_LO;
              end if;
            else
              tmr <= tmr + 1;
            end if;

          when LOAD =>
            if tmr = HALF - 1 then
              tmr   <= 0;
              ld_r  <= '1';
              state <= IDLE;
            else
              tmr <= tmr + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;
