## =============================================================================
## Avionics UUT Tester - Arty Z7-20 pin constraints
## Header pins follow Digilent's Arty-Z7-20-Master.xdc (ChipKit "IOn" labels).
## Stimulus line names (DIN1..DIN7, AUX) match sw/C_MainControl.h and
## docs/interface_board.md.
## =============================================================================

## 125 MHz board clock (H16) -> Clocking Wizard -> 50 MHz system clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];

## Reset button (BTN0) and HMI programming switch (SW0)
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports { reset }];
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports { hmi_prog }];

## Relay control U13..U25 (via CD4504B level shifters U26-U28 and NPN drivers)
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[0]  }]; # IO0  RelayCont_1  U13  UUT 28 V power
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[1]  }]; # IO1  RelayCont_2  U14  AUX   28 V / open
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[2]  }]; # IO2  RelayCont_3  U15  DIN1  select: +28 V / +0.7 V
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[3]  }]; # IO3  RelayCont_4  U16  DIN1  connect
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[4]  }]; # IO4  RelayCont_5  U17  DIN2  +28 V
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[5]  }]; # IO5  RelayCont_6  U18  DIN2  analog level from the DAC
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[6]  }]; # IO6  RelayCont_7  U19  DIN3  +0.7 V / open
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[7]  }]; # IO7  RelayCont_8  U20  DIN4  select: +28 V / +0.7 V
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[8]  }]; # IO8  RelayCont_9  U21  DIN4  connect
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[9]  }]; # IO9  RelayCont_10 U22  DIN5  GND / open (sensed on IO39)
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[10] }]; # IO10 RelayCont_11 U23  DIN6  select: +3 V / +0.7 V
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[11] }]; # IO11 RelayCont_12 U24  DIN6  connect (off = line return)
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { RelayCont[12] }]; # IO12 RelayCont_13 U25  DIN7  +5 V / open

## LTC2327-16 ADC (U2)
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { ADC_BUSY }]; # IO13
set_property -dict { PACKAGE_PIN U5  IOSTANDARD LVCMOS33 } [get_ports { ADC_SDO  }]; # IO26
set_property -dict { PACKAGE_PIN V5  IOSTANDARD LVCMOS33 } [get_ports { ADC_CNV  }]; # IO27
set_property -dict { PACKAGE_PIN V6  IOSTANDARD LVCMOS33 } [get_ports { ADC_CLK  }]; # IO28

## DAC8043 (U3)
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports { DAC_SDI }]; # IO29
set_property -dict { PACKAGE_PIN V7  IOSTANDARD LVCMOS33 } [get_ports { DAC_CLK }]; # IO30
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports { DAC_LD  }]; # IO31

## UM232R USB-UART bridge (U8) - HMI programming
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports { UM232R_TX }]; # IO32 <- UM232R TXD
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports { UM232R_RX }]; # IO33 -> UM232R RXD

## Nextion NX4827T043 touch screen (U4)
set_property -dict { PACKAGE_PIN W10 IOSTANDARD LVCMOS33 } [get_ports { LCD_RX }]; # IO34 -> screen RX
set_property -dict { PACKAGE_PIN W6  IOSTANDARD LVCMOS33 } [get_ports { LCD_TX }]; # IO35 <- screen TX

## MAX4534 4:1 analog MUX (U7): MUX[0] = A0, MUX[1] = A1, MUX[2] = EN
set_property -dict { PACKAGE_PIN Y6  IOSTANDARD LVCMOS33 } [get_ports { MUX[0] }]; # IO36 MUX_A0
set_property -dict { PACKAGE_PIN Y7  IOSTANDARD LVCMOS33 } [get_ports { MUX[1] }]; # IO37 MUX_A1
set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports { MUX[2] }]; # IO38 MUX_EN

## DIN5 sense: 3.3 V pull-up on the interface board, internal pull-up as backup
set_property -dict { PACKAGE_PIN Y8  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { PullUpCont* }]; # IO39

## -----------------------------------------------------------------------------
## Every off-chip interface here is slow and timed by construction (SCK/CLK
## are FSM-generated at <= 6.25 MHz, inputs go through 2-FF synchronizers or
## are polled, UARTs oversample). No I/O delay budget applies.
## -----------------------------------------------------------------------------
set_false_path -from [get_ports { reset hmi_prog ADC_BUSY ADC_SDO UM232R_TX LCD_TX PullUpCont* }]
set_false_path -to   [get_ports { RelayCont[*] MUX[*] ADC_CNV ADC_CLK DAC_SDI DAC_CLK DAC_LD UM232R_RX LCD_RX }]
