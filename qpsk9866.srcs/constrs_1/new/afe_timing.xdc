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
