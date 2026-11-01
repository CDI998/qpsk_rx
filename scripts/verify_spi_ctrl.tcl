set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build spi_ctrl_verify]
file mkdir $out
create_project -force spi_ctrl_verify [file join $out simulation] -part xc7z010clg400-1
foreach name {spi_master.v ad986x_ctrl.v} {
    add_files -norecurse [file join $root qpsk9866.srcs sources_1 new $name]
}
foreach name {tb_spi_master.sv tb_ad986x_ctrl_init.sv} {
    add_files -fileset sim_1 -norecurse [file join $root qpsk9866.srcs sim_1 new $name]
}
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach test {tb_spi_master tb_ad986x_ctrl_init} {
    set_property top $test [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    close_sim
    set log [file join $out simulation spi_ctrl_verify.sim sim_1 behav xsim simulate.log]
    file copy -force $log [file join $out ${test}.log]
    set f [open $log r]
    set result [read $f]
    close $f
    if {[string first TEST_PASS $result] < 0 || [string first Fatal: $result] >= 0} {error "Verification failed: $test"}
}
close_project
puts SPI_AND_CTRL_VERIFY_PASS
