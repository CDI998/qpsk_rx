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
set_property PROBES.FILE [file join $out top_diagnose.ltx] $device
refresh_hw_device $device
set ila [get_hw_ilas -of_objects $device]
if {[llength $ila] != 1} {error "Expected one SPI diagnostic ILA"}
set cs_probe [get_hw_probes afe_conf_cs_OBUF -of_objects $ila]
set_property TRIGGER_COMPARE_VALUE "eq1'b0" $cs_probe
set_property CONTROL.TRIGGER_POSITION 4096 $ila
run_hw_ila $ila
puts "SPI_CAPTURE_ARMED_PRESS_SYSTEM_RESET"
wait_on_hw_ila -timeout 2 $ila
write_hw_ila_data -csv_file -force [file join $out spi_after_reset.csv] [upload_hw_ila_data $ila]
puts "SPI_CAPTURE_COMPLETE=[file join $out spi_after_reset.csv]"
close_hw_manager
