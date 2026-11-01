set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build v2_diagnose]
set backup [file join $out release_backup]
set bit [file join $root qpsk9866.runs impl_1 top.bit]
set ltx [file join $root qpsk9866.runs impl_1 top.ltx]
set diagnose_xdc [file join $root qpsk9866.srcs constrs_1 new dac_diagnose.xdc]
file mkdir $out
file mkdir $backup
if {![file exists $bit] || ![file exists $ltx]} {error "Missing production V2 bitstream or probes"}
file copy -force $bit [file join $backup top_release.bit]
file copy -force $ltx [file join $backup top_release.ltx]

open_project [file join $root qpsk9866.xpr]
source [file join $root scripts setup_project.tcl]
set standard_xdc [get_files [file join $root qpsk9866.srcs constrs_1 new dac_debug.xdc]]
set_property IS_ENABLED false $standard_xdc
if {![llength [get_files -quiet $diagnose_xdc]]} {add_files -fileset constrs_1 -norecurse $diagnose_xdc}
set_property USED_IN_SYNTHESIS false [get_files $diagnose_xdc]
set_property PROCESSING_ORDER LATE [get_files $diagnose_xdc]

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {![string match {*Complete*} [get_property STATUS [get_runs synth_1]]]} {error "Diagnostic synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {![string match {*Complete*} [get_property STATUS [get_runs impl_1]]]} {error "Diagnostic implementation failed"}
open_run impl_1
if {[llength [get_debug_cores -quiet u_ila*]] != 1} {error "Expected one diagnostic ILA"}
foreach probe {0 1 2 3 4 5} {
    if {[get_property port_width [get_debug_ports u_ila_dac/probe$probe]] != 1} {error "Diagnostic probe width mismatch"}
}
write_debug_probes -force [file join $out top_diagnose.ltx]
write_bitstream -force [file join $out top_diagnose.bit]
close_design
close_project
file copy -force [file join $backup top_release.bit] $bit
file copy -force [file join $backup top_release.ltx] $ltx
puts "V2_DIAGNOSTIC_BITSTREAM=[file join $out top_diagnose.bit]"
