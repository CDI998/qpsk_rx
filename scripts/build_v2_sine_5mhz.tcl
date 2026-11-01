set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build sine_5mhz isolated]
file mkdir $out
create_project -force sine_5mhz $out -part xc7z010clg400-1

foreach name {top.v ad986x_ctrl.v spi_master.v afe.v ad986x_tx.v ad986x_rx.v sine_source.v} {
    add_files -norecurse [file join $root qpsk9866.srcs sources_1 new $name]
}
foreach name {tx_fifo rx_fifo} {
    read_ip [file join $root qpsk9866.srcs sources_1 ip $name ${name}.xci]
}
generate_target all [get_ips]
update_compile_order -fileset sources_1
set_property top top [get_filesets sources_1]
synth_design -top top -part xc7z010clg400-1

read_xdc [file join $root qpsk9866.srcs constrs_1 new ax7010.xdc]
read_xdc [file join $root qpsk9866.srcs constrs_1 new afe_timing.xdc]
read_xdc [file join $root qpsk9866.srcs constrs_1 new dac_debug.xdc]
opt_design
place_design
route_design
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} {error "Diagnostic DRC errors"}
set paths [get_timing_paths -delay_type max -quiet -max_paths 1]
if {[llength $paths] && [get_property SLACK $paths] < 0} {error "Diagnostic setup timing failed"}
set paths [get_timing_paths -delay_type min -quiet -max_paths 1]
if {[llength $paths] && [get_property SLACK $paths] < 0} {error "Diagnostic hold timing failed"}
write_debug_probes -force [file join $out top.ltx]
write_bitstream -force [file join $out top.bit]
report_timing_summary -file [file join $out timing_summary.rpt]
puts "V2_5MHZ_BITSTREAM=[file join $out top.bit]"
close_project
