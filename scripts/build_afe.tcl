set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root qpsk9866.xpr]
source [file join $root scripts setup_project.tcl]
set out [file join $root build dac_debug]
file mkdir $out
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {![string match {*Complete*} [get_property STATUS [get_runs synth_1]]]} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {![string match {*Complete*} [get_property STATUS [get_runs impl_1]]]} {error "Implementation failed"}
open_run impl_1
if {[llength [get_debug_cores -quiet u_ila*]] != 1} {error "Expected one AFE ILA"}
foreach {probe width} {0 12 1 1 2 12 3 1 4 1 5 1} {
    if {[get_property port_width [get_debug_ports u_ila_dac/probe$probe]] != $width} {
        error "Wrong ILA width for probe$probe"
    }
}
foreach {port pin} {{sys_clk} U18 {afe_reset_n} W18 {afe_pga[0]} P14 {afe_pga[1]} R14 {afe_pga[2]} Y16 {afe_pga[3]} Y17 {afe_pga[4]} V15 {afe_pga[5]} W15 {afe_conf_clk} Y14 {afe_conf_cs} W14 {afe_conf_mosi} P18 {afe_conf_miso} N17 {afe_mode} P16 {afe_clkout1} U14 {afe_tx_en} V18 {afe_txrx_clk} U15 {afe_rx_sync} T15 {afe_tx_sync} T14 {afe_rx_data[0]} U13 {afe_rx_data[1]} V13 {afe_rx_data[2]} V12 {afe_rx_data[3]} W13 {afe_rx_data[4]} T12 {afe_rx_data[5]} U12 {afe_tx_data[0]} T11 {afe_tx_data[1]} T10 {afe_tx_data[2]} B19 {afe_tx_data[3]} A20 {afe_tx_data[4]} C20 {afe_tx_data[5]} B20 {sys_rst_n} N15} {
    if {[get_property PACKAGE_PIN [get_ports $port]] ne $pin} {error "Wrong board pin for $port"}
}
set clock_exceptions [get_nets -hierarchical -quiet -filter {CLOCK_DEDICATED_ROUTE == FALSE}]
if {![llength $clock_exceptions]} {error "Expected fixed input clock exception"}
foreach net $clock_exceptions {
    if {$net ni {afe_txrx_clk_IBUF u_afe/afe_txrx_clk_IBUF}} {error "Unexpected clock exception: $net"}
}
report_clock_utilization -file [file join $out clock_utilization.rpt]
write_debug_probes -force [file join $root qpsk9866.runs impl_1 top.ltx]
report_drc -file [file join $out drc.rpt]
report_timing_summary -file [file join $out timing_summary.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
report_timing -from [get_ports {afe_rx_sync afe_rx_data[*]}] -delay_type max -max_paths 8 -file [file join $out adc_setup.rpt]
report_timing -from [get_ports {afe_rx_sync afe_rx_data[*]}] -delay_type min -max_paths 8 -file [file join $out adc_hold.rpt]
report_timing -to [get_ports {afe_tx_sync afe_tx_data[*]}] -delay_type max -max_paths 8 -file [file join $out dac_setup.rpt]
report_timing -to [get_ports {afe_tx_sync afe_tx_data[*]}] -delay_type min -max_paths 8 -file [file join $out dac_hold.rpt]
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} {error "DRC errors"}
foreach type {max min} {
    set paths [get_timing_paths -delay_type $type -quiet -max_paths 1]
    if {[llength $paths]} {
        set slack [get_property SLACK $paths]
        puts "DAC_DEBUG_SLACK_${type}=$slack"
        if {$slack < 0} {error "Timing failed: $type"}
    }
}
set f [open [file join $out bus_skew.rpt] r];set skew [read $f];close $f
if {[string first {Slack (VIOLATED)} $skew]>=0} {error "FIFO bus skew failed"}
foreach name {u_afe/u_tx_fifo u_afe/u_rx_fifo u_afe/u_ad986x_tx u_afe/u_ad986x_rx u_sine_source} {
    if {![llength [get_cells -quiet $name]]} {error "Missing functional block $name"}
}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {![string match {*Complete*} [get_property STATUS [get_runs impl_1]]]} {error "Bitstream generation failed"}
set bit [file join $root qpsk9866.runs impl_1 top.bit]
if {![file exists $bit]} {error "Bitstream missing"}
puts "DAC_DEBUG_BITSTREAM_READY=$bit"
close_project
