// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 14.11.2018
// Description: BSC chipset for OpenPiton with Sargantana that includes two
// bootroms (linux, baremetal, both with DTB), clint and plic.
//
// Note that direct system bus accesses are not yet possible due to a missing
// AXI-lite br_master <-> NOC converter module.
//
// The address bases for the individual peripherals are defined in the
// devices.xml file in OpenPiton, and should be set to
//
// Boot Rom 0xfff1010000 <length 0x10000>
// CLINT    0xfff1020000 <length 0xc0000>
// PLIC     0xfff1100000 <length 0x4000000>
//

module bsc_riscv_peripherals #(
    parameter int unsigned DataWidth       = 64,
    parameter int unsigned NumHarts        =  1,
    parameter int unsigned NumSources      =  1,
    parameter int unsigned PlicMaxPriority =  7,
    parameter bit          SwapEndianess   =  0,
    parameter logic [63:0] DmBase         = 64'hfff1010000,
    parameter logic [63:0] RomBase         = 64'hfff1010000,
    parameter logic [63:0] ClintBase       = 64'hfff1020000,
    parameter logic [63:0] PlicBase        = 64'hfff1100000
) (
    input                               clk_i,
    input                               rst_ni,
    input                               testmode_i,
    // connections to OpenPiton NoC filters
    // Debug/JTAG
    input  [DataWidth-1:0]              buf_ariane_debug_noc2_data_i,
    input                               buf_ariane_debug_noc2_valid_i,
    output                              ariane_debug_buf_noc2_ready_o,
    output [DataWidth-1:0]              ariane_debug_buf_noc3_data_o,
    output                              ariane_debug_buf_noc3_valid_o,
    input                               buf_ariane_debug_noc3_ready_i,
    // Bootrom
    input  [DataWidth-1:0]              buf_ariane_bootrom_noc2_data_i,
    input                               buf_ariane_bootrom_noc2_valid_i,
    output                              ariane_bootrom_buf_noc2_ready_o,
    output [DataWidth-1:0]              ariane_bootrom_buf_noc3_data_o,
    output                              ariane_bootrom_buf_noc3_valid_o,
    input                               buf_ariane_bootrom_noc3_ready_i,
    // CLINT
    input  [DataWidth-1:0]              buf_ariane_clint_noc2_data_i,
    input                               buf_ariane_clint_noc2_valid_i,
    output                              ariane_clint_buf_noc2_ready_o,
    output [DataWidth-1:0]              ariane_clint_buf_noc3_data_o,
    output                              ariane_clint_buf_noc3_valid_o,
    input                               buf_ariane_clint_noc3_ready_i,
    // PLIC
    input [DataWidth-1:0]               buf_ariane_plic_noc2_data_i,
    input                               buf_ariane_plic_noc2_valid_i,
    output                              ariane_plic_buf_noc2_ready_o,
    output [DataWidth-1:0]              ariane_plic_buf_noc3_data_o,
    output                              ariane_plic_buf_noc3_valid_o,
    input                               buf_ariane_plic_noc3_ready_i,
    // This selects either the BM or linux bootrom
    input                               ariane_boot_sel_i,
    // Debug sigs to cores
    output                              ndmreset_o,    // non-debug module reset
    output                              dmactive_o,    // debug module is active
    output [NumHarts-1:0]               debug_req_o,   // async debug request
    input  [NumHarts-1:0]               unavailable_i, // communicate whether the hart is unavailable (e.g.: power down)
    // JTAG
    input                               tck_i,
    input                               tms_i,
    input                               trst_ni,
    input                               td_i,
    output                              td_o,
    output                              tdo_oe_o,
    // CLINT
    input                               rtc_i,        // Real-time clock in (usually 32.768 kHz)
    output [NumHarts-1:0]               timer_irq_o,  // Timer interrupts
    output [NumHarts-1:0]               ipi_o,        // software interrupt (a.k.a inter-process-interrupt)
    // PLIC
    input  [NumSources-1:0]             irq_sources_i,
    input  [NumSources-1:0]             irq_le_i,     // 0:level 1:edge
    output [NumHarts-1:0][1:0]          irq_o         // level sensitive IR lines, mip & sip (async)
);

  localparam int unsigned AxiIdWidth    =  1;
  localparam int unsigned AxiAddrWidth  = 64;
  localparam int unsigned AxiDataWidth  = 64;
  localparam int unsigned AxiUserWidth  =  1;

  /////////////////////////////
  // Bootrom
  /////////////////////////////

  logic                    rom_req;
  logic [AxiAddrWidth-1:0] rom_addr;
  logic [AxiDataWidth-1:0] rom_rdata, rom_rdata_bm, rom_rdata_linux;

  AXI_LITE #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth )
  ) br_axi();

  axiu_axilite_to_memport #(
    .ADDR_WIDTH ( AxiAddrWidth  ),
    .DATA_WIDTH ( AxiDataWidth  )
  ) i_axi2rom (
    .clk          (clk_i       ),
    .rst          (~rst_ni     ),
    .axilite_port ( br_axi     ),
    .memport_en   ( rom_req    ),
    .memport_we   (            ),
    .memport_addr ( rom_addr   ),
    .memport_din  (            ),
    .memport_dout ( rom_rdata  )
  );

  bootrom i_bootrom_bm (
    .clk_i                   ,
    .req_i      ( rom_req   ),
    .addr_i     ( rom_addr  ),
    .rdata_o    ( rom_rdata_bm )
  );

  bootrom_linux i_bootrom_linux (
    .clk_i                   ,
    .req_i      ( rom_req   ),
    .addr_i     ( rom_addr  ),
    .rdata_o    ( rom_rdata_linux )
  );

  // we want to run in baremetal mode when using pitonstream
  assign rom_rdata = (ariane_boot_sel_i) ? rom_rdata_bm : rom_rdata_linux;

  noc_axilite_bridge #(
    .SLAVE_RESP_BYTEWIDTH   ( 8             ),
    .SWAP_ENDIANESS         ( SwapEndianess )
  ) i_bootrom_axilite_bridge (
    .clk                    ( clk_i                           ),
    .rst                    ( ~rst_ni                         ),
    // to/from NOC
    .splitter_bridge_val    ( buf_ariane_bootrom_noc2_valid_i ),
    .splitter_bridge_data   ( buf_ariane_bootrom_noc2_data_i  ),
    .bridge_splitter_rdy    ( ariane_bootrom_buf_noc2_ready_o ),
    .bridge_splitter_val    ( ariane_bootrom_buf_noc3_valid_o ),
    .bridge_splitter_data   ( ariane_bootrom_buf_noc3_data_o  ),
    .splitter_bridge_rdy    ( buf_ariane_bootrom_noc3_ready_i ),
    //axi lite signals
    //write address channel
    .m_axi_awaddr           ( br_axi.aw_addr               ),
    .m_axi_awvalid          ( br_axi.aw_valid              ),
    .m_axi_awready          ( br_axi.aw_ready              ),
    //write data channel
    .m_axi_wdata            ( br_axi.w_data                ),
    .m_axi_wstrb            ( br_axi.w_strb                ),
    .m_axi_wvalid           ( br_axi.w_valid               ),
    .m_axi_wready           ( br_axi.w_ready               ),
    //read address channel
    .m_axi_araddr           ( br_axi.ar_addr               ),
    .m_axi_arvalid          ( br_axi.ar_valid              ),
    .m_axi_arready          ( br_axi.ar_ready              ),
    //read data channel
    .m_axi_rdata            ( br_axi.r_data                ),
    .m_axi_rresp            ( br_axi.r_resp                ),
    .m_axi_rvalid           ( br_axi.r_valid               ),
    .m_axi_rready           ( br_axi.r_ready               ),
    //write response channel
    .m_axi_bresp            ( br_axi.b_resp                ),
    .m_axi_bvalid           ( br_axi.b_valid               ),
    .m_axi_bready           ( br_axi.b_ready               ),
    // non-axi-lite signals
    .w_reqbuf_size          (                                 ),
    .r_reqbuf_size          (                                 )
  );

  /////////////////////////////
  // CLINT
  /////////////////////////////

  AXI_LITE #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth )
  ) axi_clint ();

  bsc_clint #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidth   ),
    .NR_CORES       ( NumHarts     )
  ) i_clint (
    .clk_i                         ,
    .rst_ni                        ,
    .testmode_i                    ,
    .axi   ( axi_clint  ),
    .rtc_i                         ,
    .timer_irq_o                   ,
    .ipi_o
  );

  noc_axilite_bridge #(
    .SLAVE_RESP_BYTEWIDTH   ( 8             ),
    .SWAP_ENDIANESS         ( SwapEndianess )
  ) i_clint_axilite_bridge (
    .clk                    ( clk_i                         ),
    .rst                    ( ~rst_ni                       ),
    // to/from NOC
    .splitter_bridge_val    ( buf_ariane_clint_noc2_valid_i ),
    .splitter_bridge_data   ( buf_ariane_clint_noc2_data_i  ),
    .bridge_splitter_rdy    ( ariane_clint_buf_noc2_ready_o ),
    .bridge_splitter_val    ( ariane_clint_buf_noc3_valid_o ),
    .bridge_splitter_data   ( ariane_clint_buf_noc3_data_o  ),
    .splitter_bridge_rdy    ( buf_ariane_clint_noc3_ready_i ),
    //axi lite signals
    //write address channel
    .m_axi_awaddr           ( axi_clint.aw_addr         ),
    .m_axi_awvalid          ( axi_clint.aw_valid        ),
    .m_axi_awready          ( axi_clint.aw_ready       ),
    //write data channel
    .m_axi_wdata            ( axi_clint.w_data          ),
    .m_axi_wstrb            ( axi_clint.w_strb          ),
    .m_axi_wvalid           ( axi_clint.w_valid         ),
    .m_axi_wready           ( axi_clint.w_ready        ),
    //read address channel
    .m_axi_araddr           ( axi_clint.ar_addr         ),
    .m_axi_arvalid          ( axi_clint.ar_valid        ),
    .m_axi_arready          ( axi_clint.ar_ready       ),
    //read data channel
    .m_axi_rdata            ( axi_clint.r_data         ),
    .m_axi_rresp            ( axi_clint.r_resp         ),
    .m_axi_rvalid           ( axi_clint.r_valid        ),
    .m_axi_rready           ( axi_clint.r_ready         ),
    //write response channel
    .m_axi_bresp            ( axi_clint.b_resp         ),
    .m_axi_bvalid           ( axi_clint.b_valid        ),
    .m_axi_bready           ( axi_clint.b_ready         ),
    // non-axi-lite signals
    .w_reqbuf_size          (                               ),
    .r_reqbuf_size          (                               )
  );

  /////////////////////////////
  // PLIC
  /////////////////////////////

  AXI_LITE #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth )
  ) axi_plic();

  noc_axilite_bridge #(
    // this enables variable width accesses
    // note that the accesses are still 64bit, but the
    // write-enables are generated according to the access size
    .SLAVE_RESP_BYTEWIDTH   ( 0             ),
    .SWAP_ENDIANESS         ( SwapEndianess ),
    // this disables shifting of unaligned read data
    .ALIGN_RDATA            ( 0             )
  ) i_plic_axilite_bridge (
    .clk                    ( clk_i                        ),
    .rst                    ( ~rst_ni                      ),
    // to/from NOC
    .splitter_bridge_val    ( buf_ariane_plic_noc2_valid_i ),
    .splitter_bridge_data   ( buf_ariane_plic_noc2_data_i  ),
    .bridge_splitter_rdy    ( ariane_plic_buf_noc2_ready_o ),
    .bridge_splitter_val    ( ariane_plic_buf_noc3_valid_o ),
    .bridge_splitter_data   ( ariane_plic_buf_noc3_data_o  ),
    .splitter_bridge_rdy    ( buf_ariane_plic_noc3_ready_i ),
    //axi lite signals
    //write address channel
    .m_axi_awaddr           ( axi_plic.aw_addr               ),
    .m_axi_awvalid          ( axi_plic.aw_valid              ),
    .m_axi_awready          ( axi_plic.aw_ready              ),
    //write data channel
    .m_axi_wdata            ( axi_plic.w_data                ),
    .m_axi_wstrb            ( axi_plic.w_strb                ),
    .m_axi_wvalid           ( axi_plic.w_valid               ),
    .m_axi_wready           ( axi_plic.w_ready               ),
    //read address channel
    .m_axi_araddr           ( axi_plic.ar_addr               ),
    .m_axi_arvalid          ( axi_plic.ar_valid              ),
    .m_axi_arready          ( axi_plic.ar_ready              ),
    //read data channel
    .m_axi_rdata            ( axi_plic.r_data                ),
    .m_axi_rresp            ( axi_plic.r_resp                ),
    .m_axi_rvalid           ( axi_plic.r_valid               ),
    .m_axi_rready           ( axi_plic.r_ready               ),
    //write response channel
    .m_axi_bresp            ( axi_plic.b_resp                ),
    .m_axi_bvalid           ( axi_plic.b_valid               ),
    .m_axi_bready           ( axi_plic.b_ready               ),
    // non-axi-lite signals
    .w_reqbuf_size          (),
    .r_reqbuf_size          ()
  );

  bsc_plic #(
      .ADDR_WIDTH(DataWidth),
      .DATA_WIDTH(DataWidth),
      .ID_BITWIDTH(2),
      .PARAMETER_BITWIDTH(2),
      .NUM_TARGETS(NumHarts*2),
      .NUM_SOURCES(NumSources) // for example
   ) plic (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .irq_sources_i(irq_sources_i),
      .eip_targets_o(irq_o),

      .axi(axi_plic)
   );

endmodule // bsc_riscv_peripherals

