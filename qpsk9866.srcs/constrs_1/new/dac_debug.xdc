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
