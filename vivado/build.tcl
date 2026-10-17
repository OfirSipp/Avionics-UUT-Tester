# =============================================================================
# Avionics UUT Tester - rebuild the complete Vivado project from source
#
#   vivado -mode batch -source vivado/build.tcl             -> bitstream + XSA
#   vivado -mode batch -source vivado/build.tcl -tclargs bd -> block design only
#
# Output: build/uut_tester.xpr, build/uut_tester.xsa (for Vitis), reports.
#
# Block design:
#   Clocking Wizard (125 MHz board clock -> 50 MHz) + Processor System Reset
#   Zynq PS7 (runs C_MainControl) -> AXI SmartConnect -> 6 AXI GPIO + AXI UART Lite
#   RTL modules ADC_LTC, DAC8043FP2, Tone_Recognition, HMI_Prog
# Uses the Digilent Arty Z7-20 board preset when the board files are
# installed; otherwise applies the essential PS settings by hand.
# =============================================================================
set root  [file normalize [file join [file dirname [info script]] ..]]
set build [file join $root build]
set stop  [lindex $argv 0]

proc ip {name} { lindex [lsort [get_ipdefs -all xilinx.com:ip:${name}:*]] end }

# one net from "cell/pin" and "port" names
proc net {args} {
  set objs {}
  foreach a $args {
    if {[string match */* $a]} { lappend objs [get_bd_pins $a] } else { lappend objs [get_bd_ports $a] }
  }
  connect_bd_net {*}$objs
}

proc port {dir name {width 1}} {
  if {$width > 1} {
    create_bd_port -dir $dir -from [expr {$width - 1}] -to 0 $name
  } else {
    create_bd_port -dir $dir $name
  }
}

# AXI GPIO with one or two single-direction channels
proc gpio {name w1 dir1 {w2 0} {dir2 in}} {
  set cfg [list CONFIG.C_GPIO_WIDTH $w1 CONFIG.C_ALL_[expr {$dir1 eq "in" ? "INPUTS" : "OUTPUTS"}] 1]
  if {$w2} {
    lappend cfg CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH $w2 \
                CONFIG.C_ALL_[expr {$dir2 eq "in" ? "INPUTS" : "OUTPUTS"}]_2 1
  }
  set_property -dict $cfg [create_bd_cell -type ip -vlnv [ip axi_gpio] $name]
}

create_project uut_tester $build -part xc7z020clg400-1 -force
set board [lindex [lsort [get_board_parts -quiet *arty-z7-20*]] end]
if {$board ne ""} { set_property board_part $board [current_project] }
set_property target_language VHDL [current_project]

add_files [glob $root/rtl/*.vhd]
add_files -fileset constrs_1 $root/vivado/arty_z7_20.xdc
update_compile_order -fileset sources_1

# simulation: the testbenches are part of the project, so Flow Navigator ->
# Run Simulation works in the GUI. Default top: tb_ADC_DAC (runs in seconds);
# switch the sim top to tb_Tone_Recognition for the tone test (a few minutes).
set tbs [list $root/sim/Tone_Generator.vhd $root/sim/tb_ADC_DAC.vhd $root/sim/tb_Tone_Recognition.vhd]
add_files -fileset sim_1 $tbs
foreach f $tbs { set_property file_type {VHDL 2008} [get_files $f] }
set_property top tb_ADC_DAC [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

# --- block design ------------------------------------------------------------
create_bd_design system

# Zynq PS: ARM Cortex-A9 runs C_MainControl
set ps [create_bd_cell -type ip -vlnv [ip processing_system7] ps7]
if {$board ne ""} {
  apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
} else {
  set_property -dict [list \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE      {LVCMOS 1.8V} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO        {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH     {16 Bit} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE   {1} \
    CONFIG.PCW_UART0_UART0_IO            {MIO 14 .. 15}] $ps
  apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} $ps
}
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {0}] $ps

# 50 MHz system clock from the 125 MHz board clock (H16), BTN0 = Reset button
create_bd_port -dir I -type clk -freq_hz 125000000 sysclk
create_bd_port -dir I -type rst reset
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports reset]
set_property -dict [list CONFIG.PRIM_IN_FREQ {125.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000}] \
  [create_bd_cell -type ip -vlnv [ip clk_wiz] clk_wiz]
set_property CONFIG.C_EXT_RESET_HIGH {1} [create_bd_cell -type ip -vlnv [ip proc_sys_reset] rst]
net sysclk clk_wiz/clk_in1
net reset clk_wiz/reset rst/ext_reset_in
net clk_wiz/locked rst/dcm_locked

# PL peripherals: C_MainControl reaches every block through AXI GPIO
gpio gpio_relay  13 out 1 in    ;# oRelayU13..U25   | iForPullUp
gpio gpio_mux     3 out         ;# MUX A0, A1, EN
gpio gpio_adc    16 in  1 in    ;# iFromADC         | iFlagFromADC
gpio gpio_dac    12 out 1 out   ;# oForDAC          | oFlagForDAC
gpio gpio_rec_tx  1 out 1 out   ;# oBinaryRec       | oFlagBinaryRec
gpio gpio_rec_rx  2 in  1 in    ;# iRecognized      | iFlagRecognized
set_property CONFIG.C_BAUDRATE 9600 [create_bd_cell -type ip -vlnv [ip axi_uartlite] uart_screen]

foreach m {ADC_LTC DAC8043FP2 Tone_Recognition HMI_Prog} {
  create_bd_cell -type module -reference $m ${m}_0
}

# AXI: PS7 GP0 -> SmartConnect -> every peripheral, all on the 50 MHz clock
set slaves {gpio_relay gpio_mux gpio_adc gpio_dac gpio_rec_tx gpio_rec_rx uart_screen}
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI [llength $slaves]] \
  [create_bd_cell -type ip -vlnv [ip smartconnect] axi_smc]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_smc/S00_AXI]
set i 0
foreach s $slaves {
  connect_bd_intf_net [get_bd_intf_pins axi_smc/[format M%02d_AXI $i]] [get_bd_intf_pins $s/S_AXI]
  incr i
}
net clk_wiz/clk_out1 ps7/M_AXI_GP0_ACLK axi_smc/aclk rst/slowest_sync_clk \
    {*}[lmap s $slaves {format %s/s_axi_aclk $s}] \
    ADC_LTC_0/iclk DAC8043FP2_0/iclk Tone_Recognition_0/iclk
net rst/interconnect_aresetn axi_smc/aresetn
net rst/peripheral_aresetn {*}[lmap s $slaves {format %s/s_axi_aresetn $s}]
net rst/peripheral_reset ADC_LTC_0/iReset DAC8043FP2_0/iReset Tone_Recognition_0/iReset

# components <-> C_MainControl
net ADC_LTC_0/oDATA                    gpio_adc/gpio_io_i
net ADC_LTC_0/oFlag                    gpio_adc/gpio2_io_i
net gpio_dac/gpio_io_o                 DAC8043FP2_0/iData
net gpio_dac/gpio2_io_o                DAC8043FP2_0/iFlag
net gpio_rec_tx/gpio_io_o              Tone_Recognition_0/iBinaryRec
net gpio_rec_tx/gpio2_io_o             Tone_Recognition_0/iFlagBinaryRec
net Tone_Recognition_0/oRecognized     gpio_rec_rx/gpio_io_i
net Tone_Recognition_0/oFlagRecognized gpio_rec_rx/gpio2_io_i
net uart_screen/tx                     HMI_Prog_0/iScreenTx
net HMI_Prog_0/oScreenRx               uart_screen/rx

# board pins (names match vivado/arty_z7_20.xdc)
port O RelayCont 13
net gpio_relay/gpio_io_o RelayCont
port I PullUpCont
net PullUpCont gpio_relay/gpio2_io_i
port O MUX 3
net gpio_mux/gpio_io_o MUX
foreach {dir name pin} {
  I ADC_BUSY  ADC_LTC_0/iBusy
  I ADC_SDO   ADC_LTC_0/iSDO
  O ADC_CNV   ADC_LTC_0/oCNV
  O ADC_CLK   ADC_LTC_0/oSCK
  O DAC_SDI   DAC8043FP2_0/oSDT
  O DAC_CLK   DAC8043FP2_0/oCLK
  O DAC_LD    DAC8043FP2_0/oLD
  I hmi_prog  HMI_Prog_0/iProg
  I UM232R_TX HMI_Prog_0/iPcTx
  O UM232R_RX HMI_Prog_0/oPcRx
  O LCD_RX    HMI_Prog_0/oLcdRx
  I LCD_TX    HMI_Prog_0/iLcdTx
} {
  port $dir $name
  net $name $pin
}

# fixed, documented address map (matches sw/C_MainControl.h); moved via a
# scratch range first so no step overlaps whatever assign_bd_address picked
assign_bd_address
set amap {gpio_relay 0x41200000 gpio_mux 0x41210000 gpio_adc 0x41220000 gpio_dac 0x41230000
          gpio_rec_tx 0x41240000 gpio_rec_rx 0x41250000 uart_screen 0x40600000}
set i 0
foreach {cell base} $amap {
  set seg [get_bd_addr_segs ps7/Data/SEG_${cell}_*]
  set_property range 64K $seg
  set_property offset [expr {0x41300000 + $i * 0x10000}] $seg
  incr i
}
foreach {cell base} $amap {
  set_property offset $base [get_bd_addr_segs ps7/Data/SEG_${cell}_*]
}

regenerate_bd_layout
validate_bd_design
save_bd_design
catch { write_bd_layout -force -format svg -orientation landscape $build/block_design.svg }

make_wrapper -files [get_files system.bd] -top -import
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1
if {$stop eq "bd"} { return }

# --- implementation ----------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }

open_run impl_1
report_utilization -file $build/utilization.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $build/utilization_hier.rpt
report_timing_summary -file $build/timing.rpt
write_hw_platform -fixed -include_bit -force $build/uut_tester.xsa
puts "BUILD OK: $build/uut_tester.xsa"
