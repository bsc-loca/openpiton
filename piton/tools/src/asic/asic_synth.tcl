#############
#  write output files
#############

set_app_var sh_continue_on_error false
#########################################################
# Ensure all necessary environment variables are defined
#########################################################
foreach var {TARGET_NAME TOP_NAME CLK_NAME CLK_PERIOD COMPILE_COMMAND} {
    if {![info exists env($var)]} {
        puts stderr "ENV_CHECK_FAILED: $var is not defined."
        exit 1
    }
}

set TARGET_NAME $env(TARGET_NAME)
set TOP_NAME  $env(TOP_NAME)
set CLK_NAME  $env(CLK_NAME)
set CLK_PERIOD  $env(CLK_PERIOD)
set COMPILE_COMMAND $env(COMPILE_COMMAND)
set FAIL_ON_UNRESOLVED $env(FAIL_ON_UNRESOLVED)
set ELABORATE_ONLY $env(ELABORATE_ONLY)

if {$ELABORATE_ONLY eq ""} {
    set ELABORATE_ONLY 0
} else {
    set ELABORATE_ONLY [expr {$ELABORATE_ONLY != 0}]
}  

if {$FAIL_ON_UNRESOLVED eq ""} {
    set FAIL_ON_UNRESOLVED 0
} else {
    set FAIL_ON_UNRESOLVED [expr {$FAIL_ON_UNRESOLVED != 0}]
}   

# Construct the target path
set tcl_path	[file dirname [info script]] 
set TARGET_PATH "$tcl_path/${TARGET_NAME}"
set LIB     sch300mcpp64_cln07ff41001_base_ulvt_c8_tt_typical_max_0p75v_85c
set LIB_DB  /technos/ARM7FF/standardCells/sch300mcpp64_base_ulvt_c8/r14p0/db/sch300mcpp64_cln07ff41001_base_ulvt_c8_tt_typical_max_0p75v_85c.db
set period  [ expr {$CLK_PERIOD} ] 

file mkdir $TARGET_PATH
file mkdir $TARGET_PATH/WORK
file mkdir $TARGET_PATH/out
file mkdir $TARGET_PATH/report

cd $TARGET_PATH


proc write_outputs_ungroup {TARGET_PATH n} {
    #Write report files     
    report_power  > $TARGET_PATH/report/${n}_pow.txt
    report_area   > $TARGET_PATH/report/${n}_area.txt
    report_timing > $TARGET_PATH/report/${n}_tim.txt
    report_timing -path full -delay min -max_paths 10 > $TARGET_PATH/report/${n}.holdtiming
    report_timing -path full -delay max -max_paths 10 > $TARGET_PATH/report/${n}.setuptiming
    report_resources > $TARGET_PATH/report/${n}.resources
    report_constraint -verbose > $TARGET_PATH/report/${n}.constraint
    check_design > $TARGET_PATH/report/${n}.check_design
    check_timing > $TARGET_PATH/report/${n}.check_timing
    #/* always do change_names before write... */ 
    redirect change_names { change_names -rules verilog -hierarchy -verbose }
    #generate output file for IC Compiler for layout.
    write  -format ddc -output $TARGET_PATH/out/${n}_synthesized.ddc
    #create gate-level verilog synthesized file.
    write  -format verilog -output $TARGET_PATH/out/${n}_synthesized.v
    #write a design constraint file.
    write_sdc -nosplit $TARGET_PATH/out/${n}_synthesized.sdc
}

proc write_outputs_hierarchy {TARGET_PATH n} {
    #Write report files
    report_power -hierarchy > $TARGET_PATH/report/${n}_pow.txt
    report_area  -hierarchy > $TARGET_PATH/report/${n}_area.txt
    report_timing  > $TARGET_PATH/report/${n}_tim.txt
    report_timing -path full -delay min -max_paths 10 > $TARGET_PATH/report/${n}.holdtiming
    report_timing -path full -delay max -max_paths 10 > $TARGET_PATH/report/${n}.setuptiming
    report_resources > $TARGET_PATH/report/${n}.resources
    report_constraint -verbose > $TARGET_PATH/report/${n}.constraint
    check_design > $TARGET_PATH/report/${n}.check_design
    check_timing > $TARGET_PATH/report/${n}.check_timing
    #/* always do change_names before write... */ 
    redirect change_names { change_names -rules verilog -hierarchy -verbose }
    #generate output file for IC Compiler for layout.
    write -hierarchy -format ddc -output $TARGET_PATH/out/${n}_synthesized.ddc
    #create gate-level verilog synthesized file.
    write -hierarchy -format verilog -output $TARGET_PATH/out/${n}_synthesized.v
    #write a design constraint file.
    write_sdc -nosplit $TARGET_PATH/out/${n}_synthesized.sdc
}


proc set_clk {clk_name period} {
    create_clock [get_ports $clk_name] -name $clk_name -period $period
    set_fix_hold $clk_name
    set_dont_touch_network [get_clocks $clk_name]
    # set_clock_uncertainty 0.1 [get_clocks $clk_name]
    # (2) Setting additional constraints for clock signal,
    # so that clock network should be ideal network without any buffers.
    set_ideal_network [get_clocks $clk_name]
    set ALL_IN_BUT_CLK [remove_from_collection [all_inputs] [get_ports $clk_name]]
    set_input_delay -clock $clk_name 0.01 $ALL_IN_BUT_CLK
}


proc elaborate_with_capture {top_module} {
    # Make global variable visible inside the proc
    global FAIL_ON_UNRESOLVED
    # Temporary log file
    set temp_log [file join [pwd] "elaborate_temp.log"]
    # Start timing
    set start_time [clock seconds]
    # Run elaborate and capture output to log
    redirect -file -tee $temp_log {
        elaborate $top_module
    }
    set end_time [clock seconds]
    # Read log file
    if {[file exists $temp_log]} {
        set fp [open $temp_log r]
        set output [read $fp]
        close $fp
        file delete -force $temp_log
    } else {
        set output ""
    }

    # Initialize lists
    set error_message {}
    # Detect errors
    set has_error 0
    set match {^\s*Err}
    append match {or:}
    foreach line [split $output "\n"] {
        if {[regexp $match $line]} {
            set has_error 1
            lappend error_message $line
        }
    }
    # Detect unresolved references if the flag is set
    set unresolved_error 0
    set unresolved_message {}
    if {$FAIL_ON_UNRESOLVED } {
        # Scan each line individually
        foreach line [split $output "\n"] {
            if {[regexp {(unresolved reference|undefined symbol|unknown module)} $line]} {
                set unresolved_error 1
                lappend unresolved_message $line
            }
        }
    }
    # FAILURE CONDITIONS
    if {$has_error || $unresolved_error} {
        puts "=========================================="
        puts "ELABORATION FAILED"
        puts "=========================================="
        puts "Top module   : $top_module"
        puts "Elapsed time : [expr {$end_time - $start_time}] seconds"
        if {$has_error} {
            puts "ELAB error detected:"
            set error_messages [join $error_message "\n"]
            puts $error_messages
        }
        if {$unresolved_error} {
            puts "Unresolved reference detected:"
            set unresolved_messages [join $unresolved_message "\n"]
            puts $unresolved_messages   
        }
        puts "=========================================="
        return 1
    }
    puts "Elaboration completed successfully in [expr {$end_time - $start_time}] seconds"
    return 0
}



#==============================================================================
set systemTimeStart [clock seconds]
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "Starting at [clock format $systemTimeStart -format %H:%M:%S]"
puts "======================================================="
#==============================================================================

set_host_options -max_cores 16
set hdlin_sv_ieee_assignment_patterns 2

puts ""
puts ""
puts "========================="
puts "========================="
puts "SETTING LIBRARIES"
puts "========================="
puts "========================="

######################
#   set logical lib
######################
##--define paths to files
lappend SRC_HDL $tcl_path/src_hdl

# Base directory where all RAMs live
set ram_dir "$tcl_path/src_hdl/ASIC_RAMS"

# Collect all memory .v wrappers
set MEM_VERILOGS [glob -nocomplain -directory $ram_dir */*.v]

# Collect all generated memory .db files
set MEM_DBS [glob -nocomplain -directory $ram_dir */*.db]
set target_library [concat [list $LIB_DB] $MEM_DBS]
# DesignWare
set synthetic_library [list dw_foundation.sldb]
# Link library = * + stdcells + memories + DW
set link_library [concat * $target_library $synthetic_library]



#check_lib

#------------------------------------------------------------------------------
# Define design library and continue
#------------------------------------------------------------------------------
define_design_lib WORK -path $TARGET_PATH/WORK

#/* do not allow wire type tri in the netlist */
set verilogout_no_tri true

#/* to fix those pesky escaped names */
#/* the following variable was obsoleted in 3.1 */
#/* read_array_naming_style = %s_%d */
set bus_naming_style {%s[%d]}

#==============================================================================
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "  Start reading RTL files and elaborating design"
puts "======================================================="
#==============================================================================


source "$tcl_path/flist.tcl"
analyze -library WORK  -define {PITONSYS_IOCTRL} -format sverilog  $rtl_files

puts "Top module is: $TOP_NAME"
if {[elaborate_with_capture $TOP_NAME]} {
    exit 1
}

if {$ELABORATE_ONLY} {
    puts ""
    puts ""
    puts "======================================================="
    puts "======================================================="
    puts "  Elaborate only mode - exiting after successfull elaboration"
    puts "======================================================="
    exit 0
}

#==============================================================================
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts " uniquify and  link design"
puts "======================================================="
#==============================================================================

uniquify
link

#==============================================================================
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "  Setting dont_touch on all memory instances"
puts "======================================================="
#==============================================================================

set mem_files [split $MEM_VERILOGS " "]

# Iterate over each file
# Mark all memory instances as dont_touch
foreach f $mem_files {
    set base [file rootname [file tail $f]]
    puts $base
    # Build the filter as a Tcl string
    set filter_str "ref_name =~ ${base}*"
    # Now apply it
    set cells [get_cells -hier -filter $filter_str]
    set cell_names [get_object_name $cells]
    foreach c $cell_names {
        puts "set dont touch on asic mem: $c"
        set_dont_touch $c
    }
}

check_design

report_units

#run my set_clk function
set_clk $CLK_NAME $period 

#/* connect to all ports in the design, even if driven by the same net */
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]


#==============================================================================
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "  Starting synthesis using $COMPILE_COMMAND"
puts "======================================================="
#==============================================================================
# compile / compile_ultra / compile -incremental_mapping ...
eval $COMPILE_COMMAND

#==============================================================================
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "  Reporting results and writing output files"
puts "======================================================="
#==============================================================================

write_outputs_hierarchy "$TARGET_PATH" "hierarchy"
write_outputs_ungroup "$TARGET_PATH" "ungroup"

#==============================================================================
set systemTimeEnd [clock seconds]
puts ""
puts ""
puts "======================================================="
puts "======================================================="
puts "Starting at [clock format $systemTimeStart -format %H:%M:%S]"
puts "Ending at [clock format $systemTimeEnd -format %H:%M:%S]"
puts "Total elapsed time: [expr {$systemTimeEnd - $systemTimeStart}] seconds"
puts "======================================================="
#==============================================================================

exit 0

