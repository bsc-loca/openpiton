/*
 * Copyright (c) 2024, Barcelona Supercomputing Center
 * Contact: alireza.monemi [at] bsc [dot] es *          
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 *     * Neither the name of the copyright holder nor the names
 *       of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
`include "l15.tmp.h"
`include "define.tmp.h"

module metro_hpm (
    flat_tileid,
    clk,
    rst_n,
    hpm_st,
    cache_st,
    flit_st,
    pck_st,
    roi_start,// RIO (resion of interest) started by reading instruction count in csr
    roi_en,    // ROI Enabled until reading instruction count in csr again.
    inst_done, //for checking trap
    phy_pc_w
);
    import metro_mpi_pkg::*;
    input clk,rst_n;
    output roi_start,  roi_en;
    input wire [7:0]   flat_tileid;
    output [31 : 0] cache_st [11: 0];
    output reg [63 : 0] flit_st  [0: 5]; // count flit in/out to/from processor for 3 NoCs 
    output reg [63 : 0] pck_st   [0: 5][0:11]; // packet sizes histogram in/out to/from processor for 3 NoCs 
    `ifdef RTL_LOX0
    output inst_done [3:0];
    output [63:0] phy_pc_w [3:0];
    `else 
    output inst_done;
    output [63:0] phy_pc_w;
    `endif
    output reg [31 : 0] hpm_st [HPM_CNT_NUM-1 : 0];
    
    logic  [HPM_CNT_NUM-1 : 0] hpm_st_incr;
    reg  hpm_en;
    wire hpm_reset;
    wire csr_read;
    wire rd_instruction;
    
    `ifdef PITON_ARIANE
    import ariane_pkg::*;
    `define HPDC_PATH `TOP_MOD_INST.g_ariane_core.core.ariane.i_cva6.i_cva6_hpdcache_subsystem.i_hpdcache
    assign csr_read = `TOP_MOD_INST.g_ariane_core.core.ariane.i_cva6.csr_regfile_i.csr_read;
    assign rd_instruction = (`TOP_MOD_INST.g_ariane_core.core.ariane.i_cva6.csr_regfile_i.csr_addr.address == riscv::CSR_MINSTRET);
    always @(*) begin 
        hpm_st_incr = 'h0;
        if(hpm_en) begin 
            `ifdef EXTERNAL_HPM_EVENT_NUM
            hpm_st_incr [HPM_L15_ACCESS]= `TOP_MOD_INST.hpm_l15_access;
            hpm_st_incr [HPM_L15_MISS]  = `TOP_MOD_INST.hpm_l15_miss;
            hpm_st_incr [HPM_L2_ACCESS] = `TOP_MOD_INST.hpm_l2_access;
            hpm_st_incr [HPM_L2_MISS]   = `TOP_MOD_INST.hpm_l2_miss;
            `endif
            hpm_st_incr [HPM_ROI_CYCLES] =1'b1; 
            `ifdef PITON_ARIANE_HPDC
            hpm_st_incr [HPM_DCACHE_WBF_WRITE] =`HPDC_PATH.mem_req_write_wbuf_valid;
            hpm_st_incr [HPM_DCACHE_WBF_RDY]   =`HPDC_PATH.mem_req_write_wbuf_ready;
            `endif
        end  
    end
    `endif //PITON_ARIANE
    
    `ifdef PITON_SARG
    import riscv_pkg::*;
    `define SARG_INSTANT `TOP_MOD_INST.g_sarg_core.core.core_inst.subtile_inst.sargantana_inst
    `define CSR_PATH `SARG_INSTANT.csr_inst
    `define HPDC_PATH `TOP_MOD_INST.g_sarg_core.core.core_inst.dcache
    assign csr_read = `CSR_PATH.csr_read;
    assign rd_instruction = (`CSR_PATH.csr_addr.address == riscv_pkg::CSR_MINSTRET);
    integer i;
    always @(*) begin 
        hpm_st_incr = 'h0;
        if(hpm_en) begin 
            for(i=0;i<HPM_CNT_NUM-1;i++) begin 
                hpm_st_incr[i] = `SARG_INSTANT.hpm_events_d[i+1];
            end
            hpm_st_incr [HPM_ROI_CYCLES] = 1'b1;
            `ifdef PITON_ARIANE_HPDC
            hpm_st_incr [HPM_DCACHE_WBF_WRITE] =`HPDC_PATH.mem_req_write_wbuf_valid;
            hpm_st_incr [HPM_DCACHE_WBF_RDY]   =`HPDC_PATH.mem_req_write_wbuf_ready;
            `endif
        end   
    end
    `endif
    
    `ifdef PITON_LOX
    //`define CSR_PATH `TOP_MOD_INST.g_lox_core.core.core_inst.core_system_inst.escher_csr_inst
    import riscv_priv_pkg::CSR_CMD_RD;
    `define CSR_PATH `TOP_MOD_INST.g_lox_core.core.core_inst.core_system_inst.core_system_inst.riscv_csr 
    `define HPM_EVNT `TOP_MOD_INST.g_lox_core.core.core_inst.hpm_uncore_events
    `define HPDC_PATH  `TOP_MOD_INST.g_lox_core.core.core_inst.dcache
    `define CSR_MINSTRET  12'hB02
    //assign csr_read = `CSR_PATH.csr_read;
    assign csr_read = (`CSR_PATH.cmd_i == riscv_priv_pkg::CSR_CMD_RD);
    //assign rd_instruction = (`CSR_PATH.csr_addr.address == escher_csr_pkg::CSR_MINSTRET);
    assign rd_instruction = (`CSR_PATH.cmd_addr_i == `CSR_MINSTRET);
    always @(*) begin 
        hpm_st_incr = 'h0;
        if(hpm_en) begin 
            hpm_st_incr [HPM_ICACHE_REQ ]=`HPM_EVNT.icache_req;
            hpm_st_incr [HPM_ICACHE_KILL]=`HPM_EVNT.icache_kill;
            hpm_st_incr [HPM_ICACHE_MISS_KILL]=`HPM_EVNT.icache_imiss_kill;
            hpm_st_incr [HPM_ICACHE_BUSY]=`HPM_EVNT.icache_busy;
            hpm_st_incr [HPM_DCACHE_STALL]=`HPM_EVNT.dcache_stall;
            hpm_st_incr [HPM_DCACHE_STALL_REFILL]=`HPM_EVNT.dcache_stall_refill;   
            hpm_st_incr [HPM_DCACHE_RTAB_ROLLBACK]=`HPM_EVNT.dcache_rtab_rollback;   
            hpm_st_incr [HPM_DCACHE_REQ_ONHOLD]=`HPM_EVNT.dcache_req_onhold;    
            hpm_st_incr [HPM_DCACHE_PREFETCH_REQ]=`HPM_EVNT.dcache_prefetch_req;   
            hpm_st_incr [HPM_DCACHE_READ_REQ]=`HPM_EVNT.dcache_read_req;      
            hpm_st_incr [HPM_DCACHE_WRITE_REQ]=`HPM_EVNT.dcache_write_req;     
            hpm_st_incr [HPM_DCACHE_CMO_REQ]=`HPM_EVNT.dcache_cmo_req;        
            hpm_st_incr [HPM_DCACHE_UNCACHED_REQ]=`HPM_EVNT.dcache_uncached_req;    
            hpm_st_incr [HPM_DCACHE_MISS_READ_REQ]=`HPM_EVNT.dcache_miss_read_req;  
            hpm_st_incr [HPM_DCACHE_MISS_WRITE_REQ]=`HPM_EVNT.dcache_miss_write_req;
            `ifdef EXTERNAL_HPM_EVENT_NUM      
            hpm_st_incr [HPM_L15_ACCESS]= `HPM_EVNT.l15_access;
            hpm_st_incr [HPM_L15_MISS]  = `HPM_EVNT.l15_miss;
            hpm_st_incr [HPM_L2_ACCESS] = `HPM_EVNT.l2_access;
            hpm_st_incr [HPM_L2_MISS]   = `HPM_EVNT.l2_miss;
            `endif
            hpm_st_incr [HPM_ROI_CYCLES] =1'b1;
            `ifdef PITON_ARIANE_HPDC
            hpm_st_incr [HPM_DCACHE_WBF_WRITE] =`HPDC_PATH.mem_req_write_wbuf_valid;
            hpm_st_incr [HPM_DCACHE_WBF_RDY]   =`HPDC_PATH.mem_req_write_wbuf_ready;
            `endif
        end
    end
    `endif
    
    always @ (posedge clk)begin
        if(!rst_n) begin 
            hpm_en<=1'b0;
        end
        else if(csr_read & rd_instruction ) begin
            if( flat_tileid=='h0 ) begin
                if(hpm_en==1'b0 ) $display("**********START OF ROI*************** ");
                else              $display("***********END OF ROI**************** ");
            end
            hpm_en<=!hpm_en;
        end
    end
    
    //cache_st
    `define PATH1 `TOP_MOD_INST.l15.l15.dtag
    `define PATH2 `TOP_MOD_INST.l15.l15.dcache
    `ifndef PARALLEL_SRAMS
        `define PATH4 `TOP_MOD_INST.l2.data_wrap.l2_data.l2_data_array
        localparam AW2 = $clog2(L15_NUM_ENTRIES * L15_ARRAY_PER_CACHELINE);
        localaparm AW4 = $clog2(`L2_DATA_ARRAY_HEIGHT);
    `else 
        `define PATH4 `TOP_MOD_INST.l2.data_wrap.l2_data.way[0]
        localparam AW2 = $clog2(L15_NUM_ENTRIES);
        localparam AW4 = $clog2(`L2_DATA_ARRAY_HEIGHT/4);
    `endif
    `define PATH3 `TOP_MOD_INST.l2.tag_wrap.l2_tag.l2_tag_array
    localparam L15_L1D_LINE_SIZE = 64;
    localparam L15_NUM_ENTRIES = `CONFIG_L15_SIZE/L15_L1D_LINE_SIZE;
    localparam AW1 =  $clog2(L15_NUM_ENTRIES) - $clog2(`CONFIG_L15_ASSOCIATIVITY);
    localparam AW3 =`L2_TAG_INDEX_WIDTH;
    cache_stat #(
        .NAME ("l15_tag"),
        .Aw(AW1)
    ) l15_tag (
        .A(`PATH1.A),
        .CE(`PATH1.CE),
        .RDWEN(`PATH1.RDWEN),
        .clk(`PATH1.MEMCLK),
        .reset(~rst_n),
        .sum_wr(cache_st [0]),
        .total(cache_st [1])
    );
    
    cache_stat #(
        .NAME ("l15_dcache"),
        .Aw(AW2)
    ) l15_dcache (
        .A(`PATH2.A),
        .CE(`PATH2.CE),
        .RDWEN(`PATH2.RDWEN),
        .clk(`PATH2.MEMCLK),
        .reset(~rst_n),
        .sum_wr(cache_st [2]),
        .total(cache_st [3])
    );
    
    cache_stat # (
        .NAME ("l2_tag"),
        .Aw(AW3)
    ) l2_tag (
        .A(`PATH3.A),
        .CE(`PATH3.CE),
        .RDWEN(`PATH3.RDWEN),
        .clk(`PATH3.MEMCLK),
        .reset(~rst_n),
        .sum_wr(cache_st [4]),
        .total(cache_st [5])
    );
    
    cache_stat # (
        .NAME ("l2_data"),
        .Aw(AW4)
    ) l2_data (
        .A(`PATH4.addr),
        .CE(`PATH4.clk_en[0]),
        .RDWEN(`PATH4.rdw_en),
        .clk(clk),
        .reset(~rst_n),
        .sum_wr(cache_st [6]),
        .total(cache_st [7])
    );
    
    wire [63 : 0]   lat_sum , req_num;
    piton_lat_monitor #(
        .REQ_FLIT_WIDTH(`PITON_NOC1_WIDTH),
        .RSP_FLIT_WIDTH(`PITON_NOC2_WIDTH)
    )lat_mon(
        .id (`TOP_MOD_INST.flat_tileid),
        .req_valid(`TOP_MOD_INST.processor_router_valid_noc1),
        .req_flit_in(`TOP_MOD_INST.processor_router_data_noc1),
        .req_ready(`TOP_MOD_INST.router_processor_ready_noc1),
        .rsp_valid(`TOP_MOD_INST.buffer_processor_valid_noc2),
        .rsp_flit_in(`TOP_MOD_INST.buffer_processor_data_noc2),
        .rsp_ready(`TOP_MOD_INST.processor_router_ready_noc2),
        .lat_sum (lat_sum), 
        .req_num (req_num),
        .reset(!rst_n),
        .clk(clk)
    );
    assign  cache_st [8] = hpm_st[HPM_L2_ACCESS];
    assign  cache_st [9] = hpm_st[HPM_L2_MISS];
    assign  cache_st [10] = lat_sum [31 : 0];
    assign  cache_st [11] = req_num [31 : 0];
    
    /**********************
    *   flit_st  & pck_st
    **********************/
    integer cnt,siz;
    wire [5: 0] is_header;
    wire [`MSG_LENGTH_WIDTH-1 : 0] length [0: 5];
    wire [5: 0] flit_in_valid;
    wire [`PITON_NOC1_WIDTH-1 : 0] data_1;
    wire [`PITON_NOC2_WIDTH-1 : 0] data_2;
    wire [`PITON_NOC3_WIDTH-1 : 0] data_3;
    wire [`PITON_NOC1_WIDTH-1 : 0] data_4;
    wire [`PITON_NOC2_WIDTH-1 : 0] data_5;
    wire [`PITON_NOC3_WIDTH-1 : 0] data_6;
    
    assign  flit_in_valid[0] =`TOP_MOD_INST.router_buffer_data_val_noc1;
    assign  flit_in_valid[1] =`TOP_MOD_INST.router_buffer_data_val_noc2;
    assign  flit_in_valid[2] =`TOP_MOD_INST.router_buffer_data_val_noc3;
    assign  flit_in_valid[3] =`TOP_MOD_INST.buffer_router_valid_noc1;
    assign  flit_in_valid[4] =`TOP_MOD_INST.buffer_router_valid_noc2;
    assign  flit_in_valid[5] =`TOP_MOD_INST.buffer_router_valid_noc3;
    
    assign  data_1 = `TOP_MOD_INST.router_buffer_data_noc1;
    assign  data_2 = `TOP_MOD_INST.router_buffer_data_noc2;
    assign  data_3 = `TOP_MOD_INST.router_buffer_data_noc3;
    assign  data_4 = `TOP_MOD_INST.buffer_router_data_noc1;
    assign  data_5 = `TOP_MOD_INST.buffer_router_data_noc2;
    assign  data_6 = `TOP_MOD_INST.buffer_router_data_noc3;
    
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC1_WIDTH)
    )d0(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_1),
        .valid(flit_in_valid[0]),
        .ready(1'b1),
        .is_header(is_header[0]),
        .length(length[0])
    );
    
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC2_WIDTH)
    )d1(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_2),
        .valid(flit_in_valid[1]),
        .ready(1'b1),
        .is_header(is_header[1]),
        .length(length[1])
    );
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC3_WIDTH)
    )d2(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_3),
        .valid(flit_in_valid[2]),
        .ready(1'b1),
        .is_header(is_header[2]),
        .length(length[2])
    );
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC1_WIDTH)
    )d3(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_4),
        .valid(flit_in_valid[3]),
        .ready(1'b1),
        .is_header(is_header[3]),
        .length(length[3])
    );
    
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC2_WIDTH)
    )d4(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_5),
        .valid(flit_in_valid[4]),
        .ready(1'b1),
        .is_header(is_header[4]),
        .length(length[4])
    );
    hdr_pck_size_detect #(
        .FLIT_WIDTH(`PITON_NOC3_WIDTH)
    )d5(
        .reset(!rst_n),
        .clk(clk),
        .flit_in(data_6),
        .valid(flit_in_valid[5]),
        .ready(1'b1),
        .is_header(is_header[5]),
        .length(length[5])
    );
    
    always @ (posedge clk)begin 
        if(!rst_n) begin 
            for(cnt=0;cnt<6;cnt++) begin 
                flit_st[cnt] <=64'd0;  
                for(siz=0;siz<12;siz++) pck_st [cnt][siz] <=64'd0;
            end
        end else begin 
            if(roi_start)begin 
              //$display("*****RESET FLIT COUNTERS !***************");
                for(cnt=0;cnt<6;cnt++) begin 
                    flit_st[cnt] <=64'd0;
                    for(siz=0;siz<12;siz++) pck_st [cnt][siz] <=64'd0;
                end
            end else if(roi_en) begin   
                for(cnt=0;cnt<6;cnt++) begin
                    if(flit_in_valid[cnt])begin 
                        flit_st[cnt]<=flit_st[cnt]+1;
                        if(is_header[cnt] )  pck_st [cnt][length[cnt][3:0]] <= pck_st [cnt][length[cnt][3:0]]+1;
                    end
                end
            end
        end
    end
    
    /**********************
    *  hpm_st
    **********************/
    always @ (posedge clk)begin 
        if(!rst_n) begin 
            for(cnt=0;cnt<HPM_CNT_NUM;cnt++) begin
                hpm_st[cnt] <=32'd0;
            end
        end else begin 
            for(cnt=0;cnt<HPM_CNT_NUM;cnt++) begin 
                if(hpm_reset) hpm_st[cnt] <=32'd0;
                else if(hpm_st_incr[cnt]) hpm_st[cnt] <= hpm_st[cnt] +1'b1;
            end
        end
    end
    
    assign hpm_reset = (csr_read & rd_instruction) && (hpm_en == 1'b0);
    assign roi_en = hpm_en;
    assign roi_start = hpm_reset;
    
    /**********************
    *     Check Traps
    **********************/
    `ifdef RTL_LOX0
    reg spc0_inst_done [3:0];
    reg [63:0] spc0_phy_pc_w [3:0];
    `else 
    reg spc0_inst_done;
    reg [63:0] spc0_phy_pc_w;
    `endif
    
    always @ (posedge clk)begin 
        if(!rst_n) begin 
            `ifdef RTL_LOX0
                spc0_inst_done[0] <= 0;
                spc0_phy_pc_w[0] <= 0;
                spc0_inst_done[1] <= 0;
                spc0_phy_pc_w[1] <= 0;
                spc0_inst_done[2] <= 0;
                spc0_phy_pc_w[2] <= 0;
                spc0_inst_done[3] <= 0;
                spc0_phy_pc_w[3] <= 0;
            `else 
                spc0_inst_done <= 0;
                spc0_phy_pc_w <= 0;
            `endif
        end else begin
            `ifdef RTL_ARIANE0
                spc0_inst_done <= `ARIANE_CORE0.piton_pc_vld;
                spc0_phy_pc_w <= `ARIANE_CORE0.piton_pc;
            `endif
            `ifdef RTL_SARG0
                spc0_inst_done <= `SARG_CORE0.piton_pc_vld;
                spc0_phy_pc_w <= `SARG_CORE0.piton_pc;
            `endif
            `ifdef RTL_LOX0
                spc0_inst_done[0] <= `LOX_CORE0.debug_commit_valid[0] & ~`LOX_CORE0.core_csr_xcptn_valid_o & ~`LOX_CORE0.csr_core_xcptn_valid_i;            
                spc0_phy_pc_w[0] <= `LOX_CORE0.debug_commit_pc[0];
                spc0_inst_done[1] <= `LOX_CORE0.debug_commit_valid[1] & ~`LOX_CORE0.core_csr_xcptn_valid_o & ~`LOX_CORE0.csr_core_xcptn_valid_i;            
                spc0_phy_pc_w[1] <= `LOX_CORE0.debug_commit_pc[1];
                spc0_inst_done[2] <= `LOX_CORE0.debug_commit_valid[2] & ~`LOX_CORE0.core_csr_xcptn_valid_o & ~`LOX_CORE0.csr_core_xcptn_valid_i;            
                spc0_phy_pc_w[2] <= `LOX_CORE0.debug_commit_pc[2];
                spc0_inst_done[3] <= `LOX_CORE0.debug_commit_valid[3] & ~`LOX_CORE0.core_csr_xcptn_valid_o & ~`LOX_CORE0.csr_core_xcptn_valid_i;            
                spc0_phy_pc_w[3] <= `LOX_CORE0.debug_commit_pc[3];
            `endif 
        end
    end
    assign inst_done = spc0_inst_done;
    assign phy_pc_w  = spc0_phy_pc_w;
endmodule

/*********************
*    piton_lat_monitor
*********************/
module  piton_lat_monitor #(
    parameter REQ_FLIT_WIDTH = 64,
    parameter RSP_FLIT_WIDTH =64
    )(
    input  [7:0]   id,
    input req_valid ,
    input [REQ_FLIT_WIDTH-1 : 0]  req_flit_in,
    input req_ready,
    
    input rsp_valid,
    input [RSP_FLIT_WIDTH-1 : 0] rsp_flit_in,
    input rsp_ready,
    output reg [63 : 0] lat_sum, req_num,
    input reset,
    input clk
    );
    
    wire req_header;
    hdr_pck_size_detect #(
        .FLIT_WIDTH(REQ_FLIT_WIDTH)
    ) req_detect_in (
        .reset      (reset),
        .clk        (clk ),
        .flit_in    (req_flit_in),
        .valid      (req_valid ),
        .ready      (req_ready ),
        .is_header  (req_header),
        .length     ()
    );
    
    wire rsp_header;
    hdr_pck_size_detect #(
        .FLIT_WIDTH(RSP_FLIT_WIDTH)
    ) rsp_detect_in (
        .reset      (reset),
        .clk        (clk ),
        .flit_in    (rsp_flit_in),
        .valid      (rsp_valid ),
        .ready      (rsp_ready ),
        .is_header  (rsp_header),
        .length     ()
    );
    
    wire [`MSG_TYPE_WIDTH-1:0]   req_msg_type = req_flit_in [`MSG_TYPE];
    wire [`MSG_TYPE_WIDTH-1:0]   rsp_msg_type = rsp_flit_in [`MSG_TYPE];
    wire [`MSG_MSHRID_WIDTH-1 : 0] req_id     = req_flit_in [`MSG_MSHRID];
    wire [`MSG_MSHRID_WIDTH-1 : 0] rsp_id     = rsp_flit_in [`MSG_MSHRID];
    
    reg [63 : 0] clk_counter;
    
    always @ (posedge clk) begin
        if(reset) clk_counter<=0;
        else clk_counter<=clk_counter+1;
    end
    
    reg [63 : 0] time_stamp [2**`MSG_MSHRID_WIDTH-1 : 0];
    reg [2**`MSG_MSHRID_WIDTH-1 : 0] valid;
    
    always @ (posedge clk) begin 
        if(reset) begin 
            valid <=0; 
            lat_sum <=64'd0;
            req_num <=64'd0;
        end else begin 
        if(req_valid & req_ready & req_header) begin
            if(req_msg_type == `MSG_TYPE_LOAD_REQ ) begin 
             //  $display("MSG_TYPE_LOAD_REQ id:%d",req_id );
                time_stamp [req_id]<=clk_counter;
                valid      [req_id]<=1'b1;
            end
            if(req_msg_type == `MSG_TYPE_NC_LOAD_REQ ) begin 
             //   $display("MSG_TYPE_NC_LOAD_REQ id:%d ",req_id );
                time_stamp [req_id]<=clk_counter;
                valid      [req_id]<=1'b1;
            end
            if(req_msg_type == `MSG_TYPE_STORE_REQ ) begin 
             //   $display("MSG_TYPE_STORE_REQ id:%d ",req_id );
            end
        end
        if(rsp_valid & rsp_ready & rsp_header) begin 
            if(rsp_msg_type == `MSG_TYPE_DATA_ACK ) begin 
               // $display(" id:%d ", rsp_id );
                if(valid  [rsp_id ]) begin 
                    valid [rsp_id ] <= 1'b0;
                    lat_sum <= lat_sum + (clk_counter-time_stamp [rsp_id]);
                    req_num <= req_num + 1;
                 //   $display(" lat_sum:%d  req_num:%d ", lat_sum,  req_num );    
                end
            end
        end
        end//reset
    end
endmodule


/**************************
*    hdr_pck_size_detect
**************************/
module hdr_pck_size_detect  #(
    parameter FLIT_WIDTH=64
)(
    reset,
    clk,
    flit_in,
    valid,
    ready,
    is_header,
    length
);
    input reset,clk;
    input valid,ready;
    input [FLIT_WIDTH-1 : 0] flit_in;
    output  is_header;
    output [`MSG_LENGTH_WIDTH-1  : 0] length;
    
    localparam 
        CHANEL_WORLD_NUM = FLIT_WIDTH/64;
    localparam  [1:0] 
        HEADER = 1,
        BODY   = 2;
    reg [1:0] flit_type,flit_type_next; 
    wire [`MSG_LENGTH_WIDTH-1       :0] length_in      =  flit_in [ `MSG_LENGTH ];
    reg  [`MSG_LENGTH_WIDTH-1       :0] remain, remain_next;    
    always @ (*) begin
        remain_next = remain;
        flit_type_next = flit_type; 
        if(valid & ready) begin
            case(flit_type) 
            HEADER: begin 
                if (length_in >= CHANEL_WORLD_NUM ) begin 
                    flit_type_next = BODY;
                    remain_next = length_in  - CHANEL_WORLD_NUM;
                end
            end //HEADER
            BODY: begin 
                if(remain < CHANEL_WORLD_NUM) begin
                        flit_type_next = HEADER;
                end else if (remain >= CHANEL_WORLD_NUM ) begin
                        remain_next = remain  - CHANEL_WORLD_NUM;
                end
            end //BODY
        default : begin
        remain_next = remain;
            flit_type_next = flit_type; 
        end
            endcase
        end
    end//always
    
    always @ (posedge clk) begin
        if (reset)  begin  
            remain <= {`MSG_LENGTH_WIDTH{1'b0}};
            flit_type <=HEADER;
        end else begin 
            remain <= remain_next;
            flit_type <= flit_type_next;
        end
    end
    assign length    = (length_in > 11) ? 11 : length_in;
    assign is_header = (flit_type == HEADER);
endmodule


/***********
*    cache_index_coverege
************/
module cache_stat #(
    parameter NAME ="",
    parameter Aw = 10
)(
    input [Aw-1 : 0] A,
    input CE,
    input RDWEN,
    input clk,reset,
    output reg [31:0] sum_wr,
    output [31:0] total
);
    wire wr_en, rd_en;
    wire [Aw-1 : 0] addr;
    assign wr_en   = CE & (RDWEN == 1'b0);
    assign rd_en   = CE & (RDWEN == 1'b1);
    assign addr=A;
    
    reg [31 : 0] ram_wr [2**Aw-1 : 0];
    reg [31 : 0] ram_rd [2**Aw-1 : 0];
    initial begin 
        for (int i=0;i<2** Aw;i++) begin 
            ram_wr [i]=0;
            ram_rd [i]=0;
        end
    end
    
    assign  total = 2** Aw;
    always @(posedge clk) begin 
        if(reset) sum_wr <= '0;
        if(wr_en && ram_wr [addr] != {32{1'b1}} ) begin 
            if(ram_wr [addr] == 0) sum_wr ++;
            ram_wr [addr] = ram_wr [addr] +1;
        end
        if(rd_en && ram_rd [addr] != {32{1'b1}} ) ram_rd [addr] = ram_rd [addr] +1;
    end
    /*
    integer sum;
    real percent;
    final begin
        sum =0;
        percent = 0;
        for (int i=0;i<2** Aw;i++) begin 
            if (ram_wr [i] !=0 ) sum++;
        end
        percent = real'(sum) * 100 / (2**Aw); 
        $display("%s , %m , %0t : percent=%f  \n",NAME, $time,percent);
    end
    */
endmodule
