# Source after opening the project. These are native IPs, not HDL wrappers.
set root [file normalize [file join [file dirname [info script]] ..]]
set ip_dir [file join $root qpsk9866.srcs sources_1 ip]
file mkdir $ip_dir
foreach name {tx_fifo rx_fifo} {
    set xci [file join $ip_dir $name ${name}.xci]
    if {![llength [get_ips -quiet $name]]} {
        if {[file exists $xci]} {
            read_ip $xci
        } else {
            create_ip -name fifo_generator -vendor xilinx.com -library ip \
                -version 13.2 -module_name $name -dir $ip_dir
        }
    }
    set ip [get_ips $name]
    set_property -dict [list \
        CONFIG.Fifo_Implementation {Independent_Clocks_Block_RAM} \
        CONFIG.Performance_Options {First_Word_Fall_Through} \
        CONFIG.Input_Data_Width {12} CONFIG.Input_Depth {1024} \
        CONFIG.Output_Data_Width {12} CONFIG.Output_Depth {1024} \
        CONFIG.Reset_Pin {true} CONFIG.Reset_Type {Asynchronous_Reset} \
        CONFIG.Enable_Reset_Synchronization {true} \
        CONFIG.Enable_Safety_Circuit {true} CONFIG.Valid_Flag {true}] $ip
    set_property generate_synth_checkpoint false [get_files $xci]
    generate_target all $ip
}
puts "AFE_NATIVE_FIFOS_READY: 12-bit x 1024, independent clocks, FWFT, safety reset"
