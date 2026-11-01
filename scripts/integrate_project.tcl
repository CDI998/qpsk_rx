set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root qpsk9866.xpr]
source [file join $root scripts setup_project.tcl]
close_project
puts "PROJECT_FILES_UPDATED"
