set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root qpsk9866.runs impl_1 top.bit]
set ltx [file join $root qpsk9866.runs impl_1 top.ltx]

open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
puts "V2_TARGETS=$targets"
if {[llength $targets] != 1} {error "Expected exactly one JTAG target"}
current_hw_target [lindex $targets 0]
open_hw_target

set device [get_hw_devices xc7z010_1]
if {[llength $device] != 1} {error "Expected xc7z010_1"}
current_hw_device $device
set_property PROGRAM.FILE $bit $device
set_property PROBES.FILE $ltx $device
program_hw_devices $device
refresh_hw_device $device

puts "V2_PROGRAM_FILE=[get_property PROGRAM.FILE $device]"
puts "V2_PROBES_FILE=[get_property PROBES.FILE $device]"
puts "V2_CONFIG_STATUS=[get_property REGISTER.CONFIG_STATUS $device]"
puts "V2_BOOT_STATUS=[get_property REGISTER.BOOT_STATUS $device]"
set ilas [get_hw_ilas -of_objects $device]
puts "V2_ILAS=$ilas"
if {[llength $ilas] != 1} {error "Expected exactly one ILA"}
foreach ila $ilas {
    puts "V2_ILA_CELL=[get_property CELL_NAME $ila]"
    puts "V2_ILA_STATUS=[get_property STATUS.CORE_STATUS $ila]"
    puts "V2_ILA_CLOCK_HZ=[get_property STATIC.ILA_CLOCK_FREQ $ila]"
    puts "V2_ILA_PORTS=[get_property STATIC.PORTS.COUNT $ila]"
    catch {run_hw_ila -trigger_now $ila} arm_result
    puts "V2_ILA_ARM_RESULT=$arm_result"
    puts "V2_ILA_STATUS_AFTER_ARM=[get_property STATUS.CORE_STATUS $ila]"
}
close_hw_manager
