set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build afe_verify]
file mkdir $out
create_project -force afe_verify [file join $out simulation] -part xc7z010clg400-1
add_files -norecurse [glob [file join $root qpsk9866.srcs sources_1 new *.v]]
foreach name {tx_fifo rx_fifo} {read_ip [file join $root qpsk9866.srcs sources_1 ip $name ${name}.xci]}
foreach name {tb_ad986x_ctrl_init.sv tb_afe_datapath.sv} {
    add_files -fileset sim_1 -norecurse [file join $root qpsk9866.srcs sim_1 new $name]
}
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach test {tb_ad986x_ctrl_init tb_afe_datapath} {
    set_property top $test [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    close_sim
    set log [file join $out simulation afe_verify.sim sim_1 behav xsim simulate.log]
    file copy -force $log [file join $out ${test}.log]
    set f [open $log r];set result [read $f];close $f
    if {[string first "TEST_PASS" $result] < 0 || [string first "Fatal:" $result] >= 0} {error "Self-check failed: $test"}
}
close_project
puts "FULL_AFE_SIMULATIONS_PASS"
