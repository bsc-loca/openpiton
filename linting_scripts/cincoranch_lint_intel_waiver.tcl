waive_violation -add {WarnAnalyzeBBox_1110}  -comment {Physical memories do not have functional view}  -filter {(FileName =~ "sram_sp_wrapper.svp")}  -app { design } -tag { WarnAnalyzeBBox }
waive_violation -add {WarnAnalyzeBBox_1111}  -comment {Physical memories do not have functional view}  -filter {(FileName =~ "sram_sp_wrapper.sv")}   -app { design } -tag { WarnAnalyzeBBox }
waive_violation -add {WarnAnalyzeBBox_1112}  -comment {Physical memories do not have functional view}  -filter {(FileName =~ "sp_ram_asic.v")}   -app { design } -tag { WarnAnalyzeBBox }
waive_violation -add {WarnAnalyzeBBox_1113}  -comment {Physical memories do not have functional view}  -filter {(FileName =~ "dp_ram_asic.sv")}  -app { design } -tag { WarnAnalyzeBBox }
waive_violation -add CNR_HLIB_WAIVE_1  -app Lint -status Waived -tag "W164a_b"                 -filter { (FileName =~ "axilite_to_sri.sv") AND Statement =~ ".*seq_cnt_next.*" }                     -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_HLIB_WAIVE_2  -app Lint -status Waived -tag "W164a_b"                 -filter { (FileName =~ "axilite_to_sri.sv") AND Statement =~ ".*sri_addr.*" }                         -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_HLIB_WAIVE_3  -app Lint -status Waived -tag "W164a_b"                 -filter { (FileName =~ "axi_slave_rd_pipeline.sv") AND Statement =~ ".*s_N.*" }                       -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_HLIB_WAIVE_4  -app Lint -status Waived -tag "W164a_b"                 -filter { (FileName =~ "axi_slave_rd_pipeline.sv") AND Statement =~ ".*s_addr_.*" }                   -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_HLIB_WAIVE_5  -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*available_slots_o.*" }   -ignore -regex -comment {"Leave it unconnected on purpose."}
waive_violation -add CNR_HLIB_WAIVE_6  -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*current_wr_ptr_o.*" }    -ignore -regex -comment {"Leave it unconnected on purpose."}
waive_violation -add CNR_HLIB_WAIVE_7  -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*consumed_slots_o.*" }    -ignore -regex -comment {"Leave it unconnected on purpose."}
waive_violation -add CNR_HLIB_WAIVE_8  -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*rd_grants_o.*" }         -ignore -regex -comment {"Leave it unconnected on purpose."}
waive_violation -add CNR_HLIB_WAIVE_9  -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*wr_grants_o.*" }         -ignore -regex -comment {"Leave it unconnected on purpose."}
waive_violation -add CNR_HLIB_WAIVE_10 -app Lint -status Waived -tag "W287b"                   -filter { (FileName =~ "general_purpose_fifo_simple.sv") AND Statement =~ ".*current_rd_ptr_o.*" }    -ignore -regex -comment {"Leave it unconnected on purpose."}

waive_violation -add CNR_DGB_WAIVE_1  -app Lint -status Waived -tag "W164a_b"   -filter { (FileName =~ "chip_cincoranch.tmp.sv") AND Statement =~ ".*(io_systemjtag_part_number+16'd1).*" }  -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_DGB_WAIVE_2  -app Lint -status Waived -tag "W156"      -filter { (FileName =~ "chip_cincoranch.tmp.sv") AND Statement =~ ".*mst_ports(clint_dm_xbar_masters).*" }   -ignore -regex -comment {"Modport warning."}
waive_violation -add CNR_DGB_WAIVE_3  -app Lint -status Waived -tag "W287a"     -filter { (FileName =~ "tile.tmp.sv") AND Statement =~ ".*.dbr_res_val(dbr_fifo_out_valid).*" }   -ignore -regex -comment {"Modport warning."}
waive_violation -add CNR_DGB_WAIVE_4  -app Lint -status Waived -tag "UndrivenNUnloaded-ML"  -filter { (FileName =~ "tile.tmp.sv") AND Statement =~ ".*dbr_fifo_out_valid.*" }   -ignore -regex -comment {"supported in lka and lox."}

waive_violation -add CNR_INTEL_RESET_1  -app Lint -status Waived -tag "W175"  -filter { (FileName =~ "ctech_lib_doublesync_rstb.sv") }   -ignore -regex -comment {"Not applicable. Legacy file from Intel"}
waive_violation -add CNR_INTEL_RESET_2  -app Lint -status Waived -tag "W430"  -filter { (FileName =~ "ctech_lib_doublesync_rstb.sv") }   -ignore -regex -comment {"Not applicable. Legacy file from Intel"}

# FPU
waive_violation -add CNR_BSC_FPU_SCALAR_FF_EN -app Lint -status Waived -tag "FlopEConst" -filter { ( FileName =~ "fpnew_divsqrt_multi.svp" ) OR ( FileName =~ "fpnew_cast_multi.svp" ) OR ( FileName =~ "fpnew_fma.svp" ) OR ( FileName =~ "fpnew_noncomp.svp" ) } -ignore -comment {"Local waiver does not waive this after encryption"}

# Misc DM/PLIC
waive_violation -add CNR_DM_PLIC_WAIVE_11  -app Lint -status Waived -tag "W164a_b"             -filter { (FileName =~ "simple_dm.sv") AND Statement =~ ".*data_addr.*" }                      -ignore -regex -comment {"Harmless carry bit."}
waive_violation -add CNR_DM_PLIC_WAIVE_12  -app Lint -status Waived -tag "W240"                -filter { (FileName =~ "clint.sv") AND Statement =~ ".*sri_addr_i.*" }                         -ignore -regex -comment {"Unused address bits"}
waive_violation -add CNR_DM_PLIC_WAIVE_13  -app Lint -status Waived -tag "UnloadedInPort-ML"   -filter { (FileName =~ "clint.sv") AND Statement =~ ".*sri_addr_i.*" }                         -ignore -regex -comment {"Unused address bits"}
waive_violation -add CNR_DM_PLIC_WAIVE_14  -app Lint -status Waived -tag "W240"                -filter { (FileName =~ "plic_target_slice.sv") AND Statement =~ ".*flush_cmp_pipeline_i.*" }   -ignore -regex -comment {"Usage depends on parameters"}
waive_violation -add CNR_DM_PLIC_WAIVE_15  -app Lint -status Waived -tag "UnloadedInPort-ML"   -filter { (FileName =~ "plic_target_slice.sv") AND Statement =~ ".*flush_cmp_pipeline_i.*" }   -ignore -regex -comment {"Depends on parameters"}
