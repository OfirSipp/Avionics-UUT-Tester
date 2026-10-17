-- =============================================================================
-- ADC_LTC : LTC2327-16 ADC readout
--
-- Converts continuously. Every SAMPLE_DIV clocks:
--   1. oCNV high for 2 clocks           -> the LTC2327 starts a conversion, BUSY rises
--   2. wait for iBusy to fall           -> the MSB is already driven on SDO
--   3. 16 x { oSCK low, sample iSDO, oSCK high } -> 16 bits, MSB first
--      (15 SCK rising edges in total: the MSB needs none)
--   4. oDATA <= the 16-bit two's-complement result, oFlag <= '1'
--
-- oFlag is '1' while oDATA holds a complete sample and '0' while the next word
-- is being shifted in, so C_MainControl takes oDATA on a rising edge of oFlag
-- (iFlagFromADC). oDATA itself only changes together with that rising edge.
--
-- Timing notes (iclk = 50 MHz, defaults):
--   * iBusy and iSDO are asynchronous to iclk -> 2-FF synchronizers.
--   * iSDO is sampled at the END of the SCK-low phase. The value seen there was
--     captured (2*SCK_HALF - 3) clocks after the SCK edge that changed it, so
--     SCK_HALF >= 3 leaves >= 60 ns for tDSDO + pad/board delay.
--   * conversion (~1.5 us) + readout (31 * SCK_HALF clocks = 2.5 us) must fit
--     in SAMPLE_DIV clocks.
--   * All pins are driven straight from flip-flops (glitch-free SCK/CNV).
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity ADC_LTC is
  generic (
    SAMPLE_DIV : positive := 250;  -- iclk cycles per conversion (50 MHz / 250 = 200 kS/s)
    SCK_HALF   : positive := 4     -- iclk cycles per SCK half period (6.25 MHz SCK)
  );
  port (
    iclk   : in  std_logic;                      -- 50 MHz system clock
    iReset : in  std_logic;                      -- '1' = reset (project Reset button)
    iSDO   : in  std_logic;                      -- LTC2327 SDO  (IO26)
    iBusy  : in  std_logic;                      -- LTC2327 BUSY (IO13)
    oCNV   : out std_logic;                      -- LTC2327 CNV  (IO27)
    oSCK   : out std_logic;                      -- LTC2327 SCK  (IO28)
    oDATA  : out std_logic_vector(15 downto 0);  -- sample -> iFromADC
    oFlag  : out std_logic                       -- '1' = oDATA can be read -> iFlagFromADC
  );
  attribute X_INTERFACE_INFO      : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO      of iReset : signal is "xilinx.com:signal:reset:1.0 iReset RST";
  attribute X_INTERFACE_PARAMETER of iReset : signal is "POLARITY ACTIVE_HIGH";
end entity;

architecture rtl of ADC_LTC is
  type state_t is (IDLE, CONVERT, WAIT_BUSY, SCK_LO, SCK_HI);
  signal state     : state_t := IDLE;
  signal rate_cnt  : natural range 0 to SAMPLE_DIV - 1 := 0;
  signal tmr       : natural range 0 to 7 + SCK_HALF := 0;
  signal bit_cnt   : natural range 0 to 15 := 0;
  signal shreg     : std_logic_vector(15 downto 0) := (others => '0');
  signal busy_sync : std_logic_vector(1 downto 0) := (others => '0');
  signal sdo_sync  : std_logic_vector(1 downto 0) := (others => '0');
  signal cnv_r     : std_logic := '0';
  signal sck_r     : std_logic := '0';
  signal data_r    : std_logic_vector(15 downto 0) := (others => '0');
  signal flag_r    : std_logic := '0';
begin

  oCNV  <= cnv_r;
  oSCK  <= sck_r;
  oDATA <= data_r;
  oFlag <= flag_r;

  process (iclk)
  begin
    if rising_edge(iclk) then
      busy_sync <= busy_sync(0) & iBusy;
      sdo_sync  <= sdo_sync(0)  & iSDO;

      if iReset = '1' then
        state    <= IDLE;
        rate_cnt <= 0;
        cnv_r    <= '0';
        sck_r    <= '0';
        data_r   <= (others => '0');
        flag_r   <= '0';
      else
        -- conversion-rate tick
        if rate_cnt = SAMPLE_DIV - 1 then
          rate_cnt <= 0;
        else
          rate_cnt <= rate_cnt + 1;
        end if;

        case state is
          when IDLE =>
            if rate_cnt = 0 then
              cnv_r <= '1';
              tmr   <= 0;
              state <= CONVERT;
            end if;

          -- CNV high for 2 clocks, then 4 guard clocks so the synchronized
          -- BUSY has certainly gone high before we start waiting for it to fall
          when CONVERT =>
            tmr <= tmr + 1;
            if tmr = 1 then
              cnv_r <= '0';
            elsif tmr = 5 then
              state <= WAIT_BUSY;
            end if;

          when WAIT_BUSY =>
            if busy_sync(1) = '0' then
              tmr     <= 0;
              bit_cnt <= 15;
              flag_r  <= '0';                -- new word on its way
              state   <= SCK_LO;
            end if;

          when SCK_LO =>
            if tmr = SCK_HALF - 1 then
              tmr   <= 0;
              shreg <= shreg(14 downto 0) & sdo_sync(1);
              if bit_cnt = 0 then
                data_r <= shreg(14 downto 0) & sdo_sync(1);
                flag_r <= '1';
                state  <= IDLE;
              else
                bit_cnt <= bit_cnt - 1;
                sck_r   <= '1';              -- rising edge: ADC shifts next bit
                state   <= SCK_HI;
              end if;
            else
              tmr <= tmr + 1;
            end if;

          when SCK_HI =>
            if tmr = SCK_HALF - 1 then
              tmr   <= 0;
              sck_r <= '0';
              state <= SCK_LO;
            else
              tmr <= tmr + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;
