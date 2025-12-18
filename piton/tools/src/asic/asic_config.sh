#!/bin/bash

target="7n"  # Output directory name where the synthesis results will be stored
top="chip"   # Top module name
clk_name="core_ref_clk" # clock signal name
clk_period=1     # 1Ghz, time unit is ns
fail_on_unresolved=1 # Set to 1 to fail on unresolved references during synthesis

# Choose synthesis tool. E.g:
#   compile_command="compile"
#   compile_command="compile -incremental_mapping"
#   compile_command="compile_ultra"

compile_command="compile"

# List of ASIC macros passes to RTL files
asic_macros=(
    "PITON_ASIC_SYNTH" \
    "SYNTHESIZABLE_BRAM" \
    "SRAM_IP" \
)

# List of macros removed from RTL files (from config.v file)
remove_macros=(
    "SIM_COMMIT_LOG"
    "SIM_COMMIT_LOG_DPI"
)

# List of exceptions to not included in asic file list
flist_exceptions=( \
    memory_library \
    instr_tracer.sv \
    konata_behav.sv \
    l2_behav.sv \
    rename_checking_behav.sv \
    commit_log_behav.sv \
    async_fifo_mon.tmp.v \
    ciop_iob.tmp.v \
    cmp_l15_messages_mon.tmp.v \
    cmp_pcxandcpx.v \
    dmbr_mon.tmp.v \
    exu_mon.v \
    icache_mutex_mon.v \
    iob_mon.v \
    jtag_mon.tmp.v \
    l2_mon.tmp.v \
    l_cache_mon.v \
    lsu_mon.tmp.v \
    lsu_mon2.tmp.v \
    manycore_network_mon.tmp.v \
    mask_mon.v \
    monitor.tmp.v \
    multicycle_mon.tmp.v \
    nc_inv_chk.v \
    nukeint_mon.v \
    one_hot_mux_mon.v \
    pc_cmp.tmp.v \
    pc_muxsel_mon.v \
    sas_intf.v \
    sas_task.v \
    sas_tasks.tmp.v \
    slam_init.tmp.v \
    softint_mon.v \
    stb_ovfl_mon.v \
    thrfsm_mon.v \
    tlu_mon.v \
    tso_mon.tmp.v \
) 

export TARGET_NAME="$target"
export TOP_NAME="$top"
export CLK_NAME="$clk_name"
export CLK_PERIOD="$clk_period"
export COMPILE_COMMAND="$compile_command"
export FAIL_ON_UNRESOLVED="$fail_on_unresolved"
