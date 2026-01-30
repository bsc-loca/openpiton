// Modified by Barcelona Supercomputing Center on March 3rd, 2022
// ========== Copyright Header Begin ============================================
// Copyright (c) 2019 Princeton University
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ========== Copyright Header End ============================================

`include "mc_define.h"
`include "define.tmp.h"
`include "noc_axi4_bridge_define.vh"
import noc_axi4_bridge_pkg::*;


module noc_axi4_bridge_ser #(
  parameter SWAP_ENDIANESS = 0 // swap endianess, needed when used in conjunction with a little endian core like Ariane
) (
  input wire clk, 
  input wire rst_n, 

  input  wire [`MSG_HEADER_WIDTH-1:0] header_in, 
  input  wire [`AXI4_DATA_WIDTH-1:0] data_in, 
  input  wire in_val, 
  output wire in_rdy, 

  output wire [`PITON_NOC3_WIDTH-1:0] flit_out, 
  output wire flit_out_val, 
  input  wire flit_out_rdy 
);

// states
reg [1:0] state;
localparam ACCEPT = 2'd0;
localparam SEND_HEADER = 2'd1;
localparam SEND_DATA = 2'd2;

reg [`AXI4_DATA_WIDTH-1:0] data_in_f;
reg [`NOC_DATA_WIDTH-1:0] resp_header;
reg [`MSG_DATA_SIZE_WIDTH -1:0] dat_size_log_f;

localparam NOC_WORD_NUM = `PITON_NOC3_WIDTH / `NOC_DATA_WIDTH;

wire [`PITON_NOC3_WIDTH -1:0] data_swapped;

genvar i;
generate 
  for (i=0;i<NOC_WORD_NUM;i++ ) begin : swap
    if (i < (`AXI4_DATA_WIDTH/`NOC_DATA_WIDTH)) begin
      assign data_swapped [(i+1)*`NOC_DATA_WIDTH-1 : i*`NOC_DATA_WIDTH ]  = 
        SWAP_ENDIANESS ? swapData(data_in_f[(i+1)*`NOC_DATA_WIDTH-1 : i*`NOC_DATA_WIDTH ], dat_size_log_f) :
        data_in_f[(i+1)*`NOC_DATA_WIDTH-1 : i*`NOC_DATA_WIDTH ];
    end else begin
      assign data_swapped [(i+1)*`NOC_DATA_WIDTH-1 : i*`NOC_DATA_WIDTH ] = '0;
    end
  end//for
  case (`PITON_NOC3_WIDTH)
     64: assign flit_out = (state ==  SEND_HEADER) ? resp_header : data_swapped;
     default: assign flit_out = (state ==  SEND_HEADER) ? {data_swapped[(NOC_WORD_NUM-1)*`NOC_DATA_WIDTH-1 : 0],resp_header} : data_swapped;
  endcase
endgenerate

wire in_go = in_val & in_rdy;
wire flit_out_go = flit_out_val & flit_out_rdy;

reg [`MSG_LENGTH_WIDTH-1:0] remaining_flits;
assign flit_out_val = (state == SEND_HEADER) || (state == SEND_DATA);
assign in_rdy = (state == ACCEPT);


always_ff @(posedge clk)
  if(~rst_n) state <= ACCEPT;
  else
    //case (state) //suppressing STARC05-2.11.3.1 lint warning (Combinational and sequential parts of an FSM described in same always)
      if ((state ^ ACCEPT)==0) begin
        state <= in_val ? SEND_HEADER : ACCEPT;
      end
      else if ((state ^ SEND_HEADER) == '0) begin
        if (flit_out_rdy) begin
          if (resp_header[`MSG_LENGTH] == 0) begin
            state <= ACCEPT;
          end
          else begin
            state <= (resp_header[`MSG_LENGTH]> (NOC_WORD_NUM-1)) ? SEND_DATA :ACCEPT ;
            remaining_flits <= 
              (NOC_WORD_NUM==1)? resp_header[`MSG_LENGTH]: //64-bit 
              (resp_header[`MSG_LENGTH] > NOC_WORD_NUM) ? resp_header[`MSG_LENGTH] - (NOC_WORD_NUM - 1) : 0; //other widths
          end
        end
      end
      else if ((state ^ SEND_DATA) == '0) begin
        if (remaining_flits < (NOC_WORD_NUM + `MSG_LENGTH_WIDTH'b1)) begin
          state <= flit_out_rdy ? ACCEPT : SEND_DATA;
        end
        else begin
          state <= SEND_DATA;
          remaining_flits <= flit_out_rdy ? remaining_flits - NOC_WORD_NUM : remaining_flits;
        end
      end
      else begin
        // should never end up here
        state <= 2'b0;
        remaining_flits <= `MSG_LENGTH_WIDTH'b0;
      end
    //endcase // state

wire [`MSG_DATA_SIZE_WIDTH -1:0] dat_size_log;
wire [$clog2(`AXI4_DATA_WIDTH/8)-1:0] dummy_offset;
noc_extractSize ser_extractSize(
                .header  (header_in),
                .size_log(dat_size_log),
                .offset  (dummy_offset));

wire [`MSG_LENGTH_WIDTH-1:0] dat_payload_len = 1 << clip2zer($signed({{(32-`MSG_DATA_SIZE_WIDTH){1'b0}},dat_size_log}) - $clog2(`NOC_DATA_WIDTH/8));

always_ff @(posedge clk)
        if (in_go) begin
          resp_header[`MSG_DST_CHIPID  ]     <= header_in[`MSG_SRC_CHIPID];
          resp_header[`MSG_DST_X       ]     <= header_in[`MSG_SRC_X     ];
          resp_header[`MSG_DST_Y       ]     <= header_in[`MSG_SRC_Y     ];
          resp_header[`MSG_DST_FBITS   ]     <= header_in[`MSG_SRC_FBITS ];
          resp_header[`MSG_MSHRID      ]     <= header_in[`MSG_MSHRID    ];
          resp_header[`MSG_OPTIONS_1   ]     <= {`MSG_OPTIONS_1_WIDTH{1'b0}};
          dat_size_log_f                     <= dat_size_log;
          data_in_f                          <= data_in;
          case (header_in[`MSG_TYPE])
            `MSG_TYPE_LOAD_MEM: begin
              resp_header[`MSG_TYPE    ]     <= `MSG_TYPE_LOAD_MEM_ACK;
              resp_header[`MSG_LENGTH  ]     <= `PAYLOAD_LEN; 
            end
            `MSG_TYPE_STORE_MEM: begin
              resp_header[`MSG_TYPE    ]     <= `MSG_TYPE_STORE_MEM_ACK;
              resp_header[`MSG_LENGTH  ]     <= 0;
            end
            `MSG_TYPE_NC_LOAD_REQ: begin
              resp_header[`MSG_TYPE    ]     <= `MSG_TYPE_NC_LOAD_MEM_ACK;
              resp_header[`MSG_LENGTH  ]     <= dat_payload_len; // flexible data packet length, required for `define L2_SEND_NC_REQ
            end
            `MSG_TYPE_NC_STORE_REQ: begin
              resp_header[`MSG_TYPE    ]     <= `MSG_TYPE_NC_STORE_MEM_ACK;
              resp_header[`MSG_LENGTH  ]     <= 0;
            end
            default: begin
              // shouldn't end up herere
              resp_header[`MSG_TYPE    ]     <= `MSG_TYPE_WIDTH'b0;
              resp_header[`MSG_LENGTH  ]     <= `MSG_LENGTH_WIDTH'b0;
            end
          endcase // header_in[`MSG_TYPE]
        end
        else if (flit_out_go) begin
          if((state != SEND_HEADER)) data_in_f    <= data_in_f >> `PITON_NOC3_WIDTH;
          else if(NOC_WORD_NUM>1) begin 
             // we are sending data with one hdr
            if((state == SEND_HEADER)) data_in_f    <= data_in_f >> (`PITON_NOC3_WIDTH - `NOC_DATA_WIDTH);
          end
        end

// wire [`MSG_DST_CHIPID_WIDTH-1:0] resp_dst_chipid = resp_header[`MSG_DST_CHIPID];
// wire [`MSG_DST_X_WIDTH     -1:0] resp_dst_x      = resp_header[`MSG_DST_X];
// wire [`MSG_DST_Y_WIDTH     -1:0] resp_dst_y      = resp_header[`MSG_DST_Y];
// wire [`MSG_DST_FBITS_WIDTH -1:0] resp_dst_fbits  = resp_header[`MSG_DST_FBITS];

endmodule
