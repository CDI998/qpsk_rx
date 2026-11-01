set project_root [file normalize [file join [file dirname [info script]] ..]]
if {[file normalize [get_property DIRECTORY [current_project]]] ne $project_root} {
    error "Open qpsk9866 before running this script"
}
foreach name {top.v ad986x_ctrl.v spi_master.v afe.v ad986x_tx.v ad986x_rx.v sine_source.v} {
    set path [file join $project_root qpsk9866.srcs sources_1 new $name]
    if {![llength [get_files -quiet $path]]} {add_files -norecurse $path}
}
foreach name {tx_fifo rx_fifo} {
    set path [file join $project_root qpsk9866.srcs sources_1 ip $name ${name}.xci]
    if {[file exists $path] && ![llength [get_files -quiet $path]]} {read_ip $path}
}
foreach name {ax7010.xdc} {
    set path [file join $project_root qpsk9866.srcs constrs_1 new $name]
    if {![llength [get_files -quiet $path]]} {add_files -fileset constrs_1 -norecurse $path}
}
foreach name {tb_spi_master.sv tb_ad986x_ctrl_init.sv tb_afe_datapath.sv} {
    set path [file join $project_root qpsk9866.srcs sim_1 new $name]
    if {![llength [get_files -quiet $path]]} {add_files -fileset sim_1 -norecurse $path}
    set_property USED_IN_SYNTHESIS false [get_files $path]
    set_property USED_IN_IMPLEMENTATION false [get_files $path]
}
set_property top top [get_filesets sources_1]
# Integrated sine / ADC datapath verification.
set_property top tb_afe_datapath [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Keep one user XDC; remove stale entries from an already-open project.
foreach name {afe_timing.xdc dac_debug.xdc dac_diagnose.xdc} {
    set stale [get_files -quiet */$name]
    if {[llength $stale]} {remove_files $stale}
}
set board_xdc [get_files [file join $project_root qpsk9866.srcs constrs_1 new ax7010.xdc]]
set_property IS_ENABLED true $board_xdc
set_property USED_IN_SYNTHESIS false $board_xdc
set_property USED_IN_IMPLEMENTATION true $board_xdc
set_property PROCESSING_ORDER LATE $board_xdc
