# Temporary V2 clock-start diagnostic: keep one ILA and six one-bit probes.
# The ILA uses sys_clk so it remains usable while the AFE clock is stopped.
create_debug_core u_ila_dac ila
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_dac]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_dac]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_dac]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_dac]
connect_debug_port u_ila_dac/clk [get_nets sys_clk_IBUF_BUFG]

set_property port_width 1 [get_debug_ports u_ila_dac/probe0]
connect_debug_port u_ila_dac/probe0 [get_nets u_afe/afe_txrx_clk_IBUF]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe1]
connect_debug_port u_ila_dac/probe1 [get_nets u_afe/afe_clk_locked]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe2]
connect_debug_port u_ila_dac/probe2 [get_nets afe_conf_mosi_OBUF]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe3]
connect_debug_port u_ila_dac/probe3 [get_nets afe_conf_miso_IBUF]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe4]
connect_debug_port u_ila_dac/probe4 [get_nets afe_reset_n_OBUF]
create_debug_port u_ila_dac probe
set_property port_width 1 [get_debug_ports u_ila_dac/probe5]
connect_debug_port u_ila_dac/probe5 [get_nets -hierarchical *afe_conf_done*]

set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets sys_clk_IBUF_BUFG]
