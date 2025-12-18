# Get tcl shell path relative to current script
set tcl_path [file dirname [info script]]
puts "Initializing lib_gen.tcl"
puts "TCL script path: $tcl_path"

######################
#   Set logical lib
######################
# Define paths to files
lappend SRC_HDL $tcl_path/src_hdl
puts "SRC_HDL paths: $SRC_HDL"

# Base directory where all RAMs live
set ram_dir "$tcl_path/src_hdl/ASIC_RAMS"
puts "RAM directory: $ram_dir"

# Collect all memory .lib files
set MEM_LIBS [glob -nocomplain -directory $ram_dir */*.lib]
puts "Found [llength $MEM_LIBS] memory .lib files."

# Loop over each memory library
foreach mem_lib $MEM_LIBS {
    set mem_name [file rootname [file tail $mem_lib]]
    set mem_db   [file join [file dirname $mem_lib] ${mem_name}.db]

    if {![file exists "$mem_db"]} {
        puts "Converting $mem_name.lib to $mem_db ..."
        read_lib $mem_lib
        write_lib $mem_name -f db -o $mem_db

        # Check if .db was generated successfully
        if {![file exists "$mem_db"]} {
            puts "ERROR: $mem_db was not generated. Something went wrong with lib gen!"
            exit 1
        } else {
            puts "Successfully generated $mem_db"
        }
    } else {
        puts "$mem_db already exists, skipping."
    }
}

puts "All memory .lib files processed successfully."
exit 0
