set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build v2_diagnose isolated]
open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets] 0]
if {$target eq ""} {error "No JTAG target"}
current_hw_target $target
open_hw_target
set device [get_hw_devices xc7z010_1]
current_hw_device $device
set_property PROGRAM.FILE [file join $out top_diagnose.bit] $device
set_property PROBES.FILE [file join $out top_diagnose.ltx] $device
program_hw_devices $device
refresh_hw_device $device
set ila [get_hw_ilas -of_objects $device]
if {[llength $ila] != 1} {error "Expected one diagnostic ILA"}
foreach probe [get_hw_probes -of_objects $ila] {
    puts "V2_SPI_PROBE=[get_property NAME $probe]"
    report_property $probe
}
close_hw_manager
