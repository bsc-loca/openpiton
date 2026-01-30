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


module noc_axi4_bridge_deser #(
    parameter SWAP_ENDIANESS = 0 // swap endianess, needed when used in conjunction with a little endian core like Ariane
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [`PITON_NOC2_WIDTH-1:0] flit_in,
    input  wire  flit_in_val,
    output wire flit_in_rdy,
    input  wire phy_init_done,

    output wire [`MSG_HEADER_WIDTH-1:0] header_out,
    output reg  [`AXI4_DATA_WIDTH-1:0]  data_out,
    output wire out_val,
    input  wire out_rdy
);

localparam ACCEPT_W1   = 3'd0;
localparam ACCEPT_W2   = 3'd1;
localparam ACCEPT_W3   = 3'd2;
localparam ACCEPT_DATA = 3'd3;
localparam SEND        = 3'd4;

reg [`NOC_DATA_WIDTH-1:0]           pkt_w1;
reg [`NOC_DATA_WIDTH-1:0]           pkt_w2;
reg [`NOC_DATA_WIDTH-1:0]           pkt_w3;
reg [`MSG_LENGTH_WIDTH-1:0]         remaining_flits; //flits remaining in current packet
reg [2:0]                           state;

assign flit_in_rdy = (state != SEND) & phy_init_done;
wire flit_in_go = flit_in_val & flit_in_rdy;
assign out_val = (state == SEND);

wire [`MSG_HEADER_WIDTH    -1:0] header_in = ((`PITON_NOC2_WIDTH > `MSG_HEADER_WIDTH) && (state == ACCEPT_W1)) ? flit_in[`MSG_HEADER_WIDTH-1:0] : header_out;
wire [`MSG_DATA_SIZE_WIDTH -1:0] dat_size_log;
wire [$clog2(`AXI4_DATA_WIDTH/8)-1:0] dummy_offset;
noc_extractSize deser_extractSize(
    .header  (header_in   ),
    .size_log(dat_size_log),
    .offset  (dummy_offset)
);

localparam NOC_WORD_NUM = `PITON_NOC2_WIDTH / `NOC_DATA_WIDTH;

wire [`NOC_DATA_WIDTH -1:0] data_swapped [NOC_WORD_NUM-1 : 0];

genvar i;
generate

for (i=0;i<NOC_WORD_NUM; i=i+1) begin : sep
    assign data_swapped[i] = SWAP_ENDIANESS ?
        swapData( flit_in[`NOC_DATA_WIDTH*(i+1)-1 : `NOC_DATA_WIDTH*i], dat_size_log) :
        flit_in[`NOC_DATA_WIDTH*(i+1)-1 : `NOC_DATA_WIDTH*i];
end//for

wire [`MSG_LENGTH_WIDTH-1:0] msg_len = flit_in[`MSG_LENGTH];
reg  [$clog2(`PAYLOAD_LEN)-1 :0] dat_flit;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus1 = dat_flit + 1;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus2 = dat_flit + 2;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus3 = dat_flit + 3;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus4 = dat_flit + 4;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus5 = dat_flit + 5;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus6 = dat_flit + 6;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus7 = dat_flit + 7;
wire [$clog2(`PAYLOAD_LEN)   :0] dat_flit_plus8 = dat_flit + 8;

if(`PITON_NOC2_WIDTH == 64) begin : w64
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            state <= ACCEPT_W1;
            data_out <= {`AXI4_DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                ACCEPT_W1: begin
                    if (flit_in_go) begin
                        state <= ACCEPT_W2;
                        remaining_flits <= msg_len-1;
                        pkt_w1 <= flit_in;
                        dat_flit <= 0;
                        data_out <= {`AXI4_DATA_WIDTH{1'b0}};
                    end
                end
                ACCEPT_W2: begin
                    if (flit_in_go) begin
                        state <= ACCEPT_W3;
                        remaining_flits <= remaining_flits - 1;
                        pkt_w2 <= flit_in;
                    end
                end
                ACCEPT_W3: begin
                    if (flit_in_go) begin
                        if (remaining_flits == 0) begin
                            state <= SEND;
                        end else begin
                            state <= ACCEPT_DATA;
                            remaining_flits <= remaining_flits - 1;
                        end
                        pkt_w3 <= flit_in;
                    end
                end
                ACCEPT_DATA: begin
                    if (flit_in_go) begin
                        if (remaining_flits == 0) begin
                            state <= SEND;
                        end else begin
                            state <= ACCEPT_DATA;
                            remaining_flits <= remaining_flits - 1;
                            dat_flit <= dat_flit + 1;
                        end
                    end
                    if (flit_in_val) begin
                        data_out[dat_flit * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[0];
                    end
                end
                SEND: begin
                    if (out_rdy) begin
                        state <= ACCEPT_W1;
                    end
                end
                default: begin
                    // should never end up here
                    state <= 3'bX;
                    remaining_flits <= `MSG_LENGTH_WIDTH'bX;
                    pkt_w1 <= `NOC_DATA_WIDTH'bX;
                    pkt_w2 <= `NOC_DATA_WIDTH'bX;
                    pkt_w3 <= `NOC_DATA_WIDTH'bX;
                end
            endcase // state
        end // main rstn conditional
    end // always_ff block
end :w64

if(`PITON_NOC2_WIDTH == 128) begin : w128
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            state <= ACCEPT_W1;
            data_out <= {`AXI4_DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                ACCEPT_W1: begin
                    if (flit_in_go) begin
                        state <= ACCEPT_W3;
                        remaining_flits <= (msg_len > (2*NOC_WORD_NUM-1)) ? (msg_len -(2*NOC_WORD_NUM-1)) : 0;
                        {pkt_w2,pkt_w1} <= flit_in ;
                        dat_flit <= 0;
                        data_out <= {`AXI4_DATA_WIDTH{1'b0}};
                    end
                end
                ACCEPT_W3: begin
                    if (flit_in_go) begin
                        if (remaining_flits == 0) begin
                            state <= SEND;
                        end else begin
                            state <= ACCEPT_DATA;
                            remaining_flits <= (remaining_flits > NOC_WORD_NUM) ? remaining_flits - NOC_WORD_NUM : 0;
                            data_out[dat_flit * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[1];
                        end
                        pkt_w3 <= flit_in[`NOC_DATA_WIDTH-1 : 0];
                    end
                end
                ACCEPT_DATA: begin
                    if (flit_in_go) begin
                        if (remaining_flits == 0) begin
                            state <= SEND;
                        end else begin
                            state <= ACCEPT_DATA;
                            remaining_flits <= (remaining_flits > NOC_WORD_NUM) ? remaining_flits - NOC_WORD_NUM : 0;
                            dat_flit <= dat_flit + 2;
                        end
                    end
                    if (flit_in_val) begin
                        data_out[dat_flit_plus1[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[0];
                        data_out[dat_flit_plus2[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[1];
                    end
                end
                SEND: begin
                    if (out_rdy) begin
                        state <= ACCEPT_W1;
                    end
                end
                default: begin
                    // should never end up here
                    state <= 3'bX;
                    remaining_flits <= `MSG_LENGTH_WIDTH'bX;
                    pkt_w1 <= `NOC_DATA_WIDTH'bX;
                    pkt_w2 <= `NOC_DATA_WIDTH'bX;
                    pkt_w3 <= `NOC_DATA_WIDTH'bX;
                end
            endcase // state
        end // main rstn block
    end // always_ff block
end // : w128

if(`PITON_NOC2_WIDTH == 256) begin : w256
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            state <= ACCEPT_W1;
            data_out <= {`AXI4_DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                ACCEPT_W1: begin
                    if (flit_in_go) begin
                        remaining_flits <= (msg_len > (2*NOC_WORD_NUM-1)) ? (msg_len -(2*NOC_WORD_NUM-1)) : 0;
                        {pkt_w3,pkt_w2,pkt_w1} <= flit_in [3*`NOC_DATA_WIDTH-1 : 0] ;
                        state <= (msg_len > (NOC_WORD_NUM-1)) ? ACCEPT_DATA : SEND;
                        dat_flit <= 0;
                        data_out <= {`AXI4_DATA_WIDTH{1'b0}};
                    end
                    if (flit_in_val) begin
                        data_out[0 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[3];
                        data_out[1 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[2 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[3 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[4 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[5 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[6 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                        data_out[7 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                    end
                end
                ACCEPT_DATA: begin
                    if (flit_in_go) begin
                        if (remaining_flits == 0) begin
                            state <= SEND;
                        end else begin
                            state <= ACCEPT_DATA;
                            remaining_flits <= (remaining_flits > NOC_WORD_NUM) ? remaining_flits - NOC_WORD_NUM : 0;
                            dat_flit <= dat_flit + 4;
                        end
                    end
                    if (flit_in_val) begin
                        data_out[dat_flit_plus1[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[0];
                        data_out[dat_flit_plus2[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[1];
                        data_out[dat_flit_plus3[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[2];
                        data_out[dat_flit_plus4[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[3];
                    end
                end
                SEND: begin
                    if (out_rdy) begin
                        state <= ACCEPT_W1;
                    end
                end
                default: begin
                    // should never end up here
                    state <= 3'bX;
                    remaining_flits <= `MSG_LENGTH_WIDTH'bX;
                    pkt_w1 <= `NOC_DATA_WIDTH'bX;
                    pkt_w2 <= `NOC_DATA_WIDTH'bX;
                    pkt_w3 <= `NOC_DATA_WIDTH'bX;
                end
            endcase // state
        end // else main reset block
    end // always_ff block
end //w256

if(`PITON_NOC2_WIDTH == 512) begin : w512
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            state <= ACCEPT_W1;
            data_out <= {`AXI4_DATA_WIDTH{1'b0}};
        end else begin
        //case (state) //suppressing STARC05-2.11.3.1 lint warning (Combinational and sequential parts of an FSM described in same always)
            if (state == ACCEPT_W1) begin
                if (flit_in_go) begin
                    remaining_flits <= (msg_len > (2*NOC_WORD_NUM-1)) ? (msg_len -(2*NOC_WORD_NUM-1)) : 0;
                    {pkt_w3,pkt_w2,pkt_w1} <= flit_in [3*`NOC_DATA_WIDTH-1 : 0];
                    state <= (msg_len > (NOC_WORD_NUM-1)) ? ACCEPT_DATA : SEND;
                    dat_flit <= 0;
                end
                if (flit_in_val) begin
                    data_out[0 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[3];
                    data_out[1 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[4];
                    data_out[2 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[5];
                    data_out[3 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[6];
                    data_out[4 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[7];
                    data_out[5 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                    data_out[6 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                    data_out[7 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= `NOC_DATA_WIDTH'h0;
                end
            end else if (state == ACCEPT_DATA) begin
                if (flit_in_go) begin
                    if (remaining_flits == 0) begin
                        state <= SEND;
                    end else begin
                        state <= ACCEPT_DATA;
                        remaining_flits <= (remaining_flits > NOC_WORD_NUM) ? remaining_flits - NOC_WORD_NUM : 0;
                        dat_flit <= dat_flit_plus8[$clog2(`PAYLOAD_LEN)-1 :0];
                    end
                end
                if (flit_in_val) begin
                    data_out[dat_flit_plus5[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[0];
                    data_out[dat_flit_plus6[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[1];
                    data_out[dat_flit_plus7[$clog2(`PAYLOAD_LEN)-1 :0] * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[2];
                end
            end else if (state == SEND) begin
                if (out_rdy) begin
                    state <= ACCEPT_W1;
                end else begin
                    // should never end up here
                    state <= 3'b0;
                    remaining_flits <= `MSG_LENGTH_WIDTH'b0;
                    pkt_w1 <= `NOC_DATA_WIDTH'b0;
                    pkt_w2 <= `NOC_DATA_WIDTH'b0;
                    pkt_w3 <= `NOC_DATA_WIDTH'b0;
                end
            end
        //endcase // state
        end // main reset block
    end // always_ff
end //w512

if(`PITON_NOC2_WIDTH == 704) begin : w704
    always_ff @(posedge clk) begin
        if(~rst_n) begin
            state    <= ACCEPT_W1;
            data_out <= {`AXI4_DATA_WIDTH{1'b0}};
        end else begin
            if (state == ACCEPT_W1) begin
                if (flit_in_go) begin
                    {pkt_w3,pkt_w2,pkt_w1} <= flit_in [3*`NOC_DATA_WIDTH-1 : 0];
                    state    <= SEND;
                    dat_flit <= 0;
                end
                if (flit_in_val) begin
                    data_out[0 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[3 ];
                    data_out[1 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[4 ];
                    data_out[2 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[5 ];
                    data_out[3 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[6 ];
                    data_out[4 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[7 ];
                    data_out[5 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[8 ];
                    data_out[6 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[9 ];
                    data_out[7 * `NOC_DATA_WIDTH +: `NOC_DATA_WIDTH] <= data_swapped[10];
                end
            end else if (state == SEND) begin
                if (out_rdy) begin
                    state <= ACCEPT_W1;
                end
            end else begin
                // should never end up here
                state <= 3'b0;
                remaining_flits <= `MSG_LENGTH_WIDTH'b0;
                pkt_w1 <= `NOC_DATA_WIDTH'b0;
                pkt_w2 <= `NOC_DATA_WIDTH'b0;
                pkt_w3 <= `NOC_DATA_WIDTH'b0;
            end
        end
    end // always_ff
end //w704
endgenerate

assign header_out = {pkt_w3, pkt_w2, pkt_w1};

endmodule
