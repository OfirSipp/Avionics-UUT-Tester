-- =============================================================================
-- HMI_Prog : touch-screen UART routing
--
-- Normally the Nextion screen (IO34 / IO35) talks to C_MainControl through
-- the AXI UART Lite. With iProg = '1' (SW0) it is wired straight to the
-- UM232R USB-UART bridge (IO32 / IO33) instead, so the PC can program the
-- screen's HMI from the Nextion editor without unplugging it.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity HMI_Prog is
  port (
    iProg     : in  std_logic;   -- '1' = HMI programming from the PC (SW0)
    iScreenTx : in  std_logic;   -- AXI UART Lite tx (oRxScreen)
    oScreenRx : out std_logic;   -- AXI UART Lite rx (iTxScreen)
    iPcTx     : in  std_logic;   -- UM232R TXD (IO32)
    oPcRx     : out std_logic;   -- UM232R RXD (IO33)
    oLcdRx    : out std_logic;   -- Nextion RX (IO34)
    iLcdTx    : in  std_logic    -- Nextion TX (IO35)
  );
end entity;

architecture rtl of HMI_Prog is
begin
  oLcdRx    <= iPcTx when iProg = '1' else iScreenTx;
  oPcRx     <= iLcdTx when iProg = '1' else '1';   -- UART idle
  oScreenRx <= '1' when iProg = '1' else iLcdTx;
end architecture;
