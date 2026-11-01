# Hardware V2: RCLK=H1-15，MODE=H1-17，CLKOUT1=H1-16；RESET=H1-4，PGA/SPI保持旧板分配。
# AX7010 J10 pin n -> AD9866 daughterboard H1 pin n.
# Source: ALINX AX7010_UG.pdf, J10 assignment, pages 36-37.
# J10 1/37/38=GND, 2=5V; 39/40=3.3V (NC on daughterboard).
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property PACKAGE_PIN N15 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports afe_reset_n]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {afe_pga[0]}]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {afe_pga[1]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {afe_pga[2]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {afe_pga[3]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {afe_pga[4]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {afe_pga[5]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports afe_conf_clk]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports afe_conf_cs]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports afe_conf_mosi]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports afe_conf_miso]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports afe_mode]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports afe_clkout1]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports afe_tx_en]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports afe_txrx_clk]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports afe_rx_sync]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports afe_tx_sync]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[0]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[1]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[2]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[3]}]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[4]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {afe_rx_data[5]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[0]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[1]}]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[2]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[3]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[4]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {afe_tx_data[5]}]
set_property DRIVE 8 [get_ports -filter {DIRECTION == OUT}]
set_property SLEW SLOW [get_ports -filter {DIRECTION == OUT}]

# AFE interface timing
# V2: RCLK on H1/J10-15/U15, SRCC N-side; scoped fabric input route.
# AD9865: OSCIN=38.4MHz, PLL x2, ADC /4, 4x DAC interpolation.
# AFE clock output is gated off until configuration and PLL settling complete.
create_clock -name afe_txrx_clk -period 26.042 [get_ports afe_txrx_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_pins u_afe/u_afe_clk_mmcm/CLKIN1]]
# RX output launches on falling RXCLK (register 0D=03); FPGA captures on rising.
# Datasheet tDV max=3ns plus a 2ns board allowance; minimum delay=0.
set_input_delay -clock afe_txrx_clk -clock_fall -max 5.000 [get_ports {afe_rx_sync afe_rx_data[*]}]
set_input_delay -clock afe_txrx_clk -clock_fall -min 0.000 [get_ports {afe_rx_sync afe_rx_data[*]}]
# FPGA launches TX on falling RXCLK; AD9865 captures on rising.
# Setup 2.5ns + 1ns board allowance; conservative hold allowance 2.5ns.
set_output_delay -clock afe_txrx_clk -max 3.500 [get_ports {afe_tx_sync afe_tx_data[*]}]
set_output_delay -clock afe_txrx_clk -min -2.500 [get_ports {afe_tx_sync afe_tx_data[*]}]
# SPI samples halfway through a 1us bit. Conservative external return/board delays.
set_input_delay -clock sys_clk -max 30.000 [get_ports afe_conf_miso]
set_input_delay -clock sys_clk -min 0.000 [get_ports afe_conf_miso]
set_multicycle_path 25 -setup -from [get_ports afe_conf_miso]
set_multicycle_path 24 -hold -from [get_ports afe_conf_miso]
# SYS and AFE are unrelated; native FIFO CDC paths are constrained separately.
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks -include_generated_clocks afe_txrx_clk]
# Native FIFO IP XDC supplies Gray-code CDC and bus-skew constraints.

# System-domain control outputs: 5ns external budget at the 50MHz system clock.
# This conservatively bounds control-pin propagation; SPI runs at only 1MHz.
set_output_delay -clock sys_clk -max 5.000 [get_ports {afe_conf_clk afe_conf_cs afe_conf_mosi afe_reset_n afe_mode afe_pga[*] afe_tx_en}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {afe_conf_clk afe_conf_cs afe_conf_mosi afe_reset_n afe_mode afe_pga[*] afe_tx_en}]

# Production ADC/DAC ILA
# DAC FIFO read and ADC FIFO write boundaries, both 12 bits, zero-padded.
# One AFE-clock ILA; debug hub uses the continuously running SYS clock.
create_debug_core u_ila_dac ila
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_dac]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_dac]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_dac]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_dac]
connect_debug_port u_ila_dac/clk [get_nets u_afe/afe_clk]
set_property port_width 12 [get_debug_ports u_ila_dac/probe0]
connect_debug_port u_ila_dac/probe0 [get_nets [list {u_afe/u_ad986x_tx/dac_sample[0]} {u_afe/u_ad986x_tx/dac_sample[1]} {u_afe/u_ad986x_tx/dac_sample[2]} {u_afe/u_ad986x_tx/dac_sample[3]} {u_afe/u_ad986x_tx/dac_sample[4]} {u_afe/u_ad986x_tx/dac_sample[5]} {u_afe/u_ad986x_tx/dac_sample[6]} {u_afe/u_ad986x_tx/dac_sample[7]} {u_afe/u_ad986x_tx/dac_sample[8]} {u_afe/u_ad986x_tx/dac_sample[9]} {u_afe/u_ad986x_tx/dac_sample[10]} {u_afe/u_ad986x_tx/dac_sample[11]}]]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe1]
connect_debug_port u_ila_dac/probe1 [get_nets u_afe/u_ad986x_tx/dac_sample_valid]
create_debug_port u_ila_dac probe
set_property port_width 12 [get_debug_ports u_ila_dac/probe2]
connect_debug_port u_ila_dac/probe2 [get_nets [list {u_afe/u_ad986x_rx/adc_sample[0]} {u_afe/u_ad986x_rx/adc_sample[1]} {u_afe/u_ad986x_rx/adc_sample[2]} {u_afe/u_ad986x_rx/adc_sample[3]} {u_afe/u_ad986x_rx/adc_sample[4]} {u_afe/u_ad986x_rx/adc_sample[5]} {u_afe/u_ad986x_rx/adc_sample[6]} {u_afe/u_ad986x_rx/adc_sample[7]} {u_afe/u_ad986x_rx/adc_sample[8]} {u_afe/u_ad986x_rx/adc_sample[9]} {u_afe/u_ad986x_rx/adc_sample[10]} {u_afe/u_ad986x_rx/adc_sample[11]}]]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe3]
connect_debug_port u_ila_dac/probe3 [get_nets u_afe/u_ad986x_rx/adc_sample_valid]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe4]
connect_debug_port u_ila_dac/probe4 [get_nets u_afe/afe_rst_n]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe5]
connect_debug_port u_ila_dac/probe5 [get_nets u_afe/afe_conf_done]
set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets sys_clk_IBUF_BUFG]
