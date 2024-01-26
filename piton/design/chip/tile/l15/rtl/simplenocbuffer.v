/*
Copyright (c) 2015 Princeton University
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Princeton University nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//==================================================================================================
//  Filename      : simplenocbuffer.v
//  Created On    : 2014-03-03 20:20:43
//  Last Modified : 2014-04-17 19:30:07
//  Revision      :
//
//  Description   :
//
//
//==================================================================================================
//simplenocbuffer.v

`include "iop.h"
`include "l15.tmp.h"
`include "define.tmp.h"

//`default_nettype none
module simplenocbuffer #(
   parameter L15_L1D_LINE_SIZE = 64,
   localparam L15_MAX_DATA_PACKETS = L15_L1D_LINE_SIZE/`NOC_BYTES_WIDTH,
   localparam NOC2_MAX_FLIT_NUMBER = (`L1I_LINE_SIZE<L15_L1D_LINE_SIZE) ? (L15_MAX_DATA_PACKETS + 1) : (4+1) //Data packets + header
) (
   input wire clk,
   input wire rst_n,
   input wire noc_in_val,
   input wire [`PITON_NOC2_WIDTH-1:0] noc_in_data,
   input wire msg_ack,
   output reg noc_in_rdy,
   output [64*NOC2_MAX_FLIT_NUMBER-1:0] msg,
   output reg msg_val
   );

localparam NOC2_MAX_FLIT_NUMBER_LOG2 = $clog2(NOC2_MAX_FLIT_NUMBER);

localparam 
    CHANEL_OUT_SIZE = `PITON_NOC2_WIDTH/64,
    BUFF_OFSET = ((64*NOC2_MAX_FLIT_NUMBER) % `PITON_NOC2_WIDTH > 0) ? 1 : 0,
    BUFF_DEPTH = ((64*NOC2_MAX_FLIT_NUMBER) / `PITON_NOC2_WIDTH ) + BUFF_OFSET,
    INDEX_WIDTH = ($clog2(BUFF_DEPTH)==0)? 1 : $clog2(BUFF_DEPTH) ;

reg [INDEX_WIDTH-1:0] index;
reg [INDEX_WIDTH-1:0] index_next;
reg [`MSG_LENGTH_WIDTH-1:0] msg_len;
reg [`NOC2_STATE_WIDTH-1:0] state;
reg [`NOC2_STATE_WIDTH-1:0] state_next;
reg [`PITON_NOC2_WIDTH-1:0] buffer [0:BUFF_DEPTH-1];
reg [`PITON_NOC2_WIDTH-1:0] buffer_next [0:BUFF_DEPTH-1];

reg [BUFF_DEPTH-1 : 0] enable;
reg [`MSG_LENGTH_WIDTH-1:0] len_captured,len_captured_next;
wire [BUFF_DEPTH * `PITON_NOC2_WIDTH-1:0] msg_tmp;
// Reset logic & sequential
genvar k;
generate
   for  (k=0; k<BUFF_DEPTH; k=k+1) begin : B_
      always @ (posedge clk) begin
         if (~rst_n) begin 
            buffer[k] <= `PITON_NOC2_WIDTH'b0;
         end else begin 
            if(enable[k]) buffer[k]<=noc_in_data;
         end
      end
      assign msg_tmp[(k+1)*`PITON_NOC2_WIDTH - 1 -: `PITON_NOC2_WIDTH] = buffer[k];
   end//for
endgenerate

assign msg = msg_tmp[64*NOC2_MAX_FLIT_NUMBER-1:0];


always @ (posedge clk)
begin

   if (~rst_n)
   begin   
      index <= 0;
      state <= 0;
      len_captured<=0;
   end
   else
   begin      
      index <= index_next;
      state <= state_next;
      len_captured<=len_captured_next;
   end
end

always @ *
begin
   index_next = index;
   len_captured_next = len_captured;
   state_next = 0;
   msg_val = 0;
   msg_len = 0;   
   noc_in_rdy = 1'b0;
   enable={BUFF_DEPTH{1'b0}};

   if (state == `NOC2_STATE_IDLE)
   begin
      noc_in_rdy = 1'b1;
      msg_len = noc_in_data[`MSG_LENGTH];
      if (noc_in_val)
      begin
         enable[0] = 1'b1;
         if (msg_len < CHANEL_OUT_SIZE)
         begin
            state_next = `NOC2_STATE_WAITING_ACK;
         end
         else
         begin
            state_next = `NOC2_STATE_RECEIVING;
            index_next = index + 1;
            len_captured_next = len_captured + CHANEL_OUT_SIZE;
         end
      end
   end
   else if (state == `NOC2_STATE_RECEIVING)
   begin
      noc_in_rdy = 1'b1;
      msg_len = buffer[0][`MSG_LENGTH];
      if (noc_in_val)
      begin
         enable[index] = 1'b1;
         if (len_captured >= msg_len)
         begin
            //if ack is asserted it means tha last msg is not yet consumed. We have to wait
            state_next = `NOC2_STATE_WAITING_ACK;
         end
         else
         begin
            state_next = `NOC2_STATE_RECEIVING;
            index_next = index + 1;
            len_captured_next = len_captured + CHANEL_OUT_SIZE;
         end
      end
      else state_next = state;
   end
   else if (state == `NOC2_STATE_WAITING_ACK)
   begin
      noc_in_rdy = 1'b0;
      msg_val = 1'b1;
      if (msg_ack)
      begin
         state_next = `NOC2_STATE_WAITING_ACK_RST;
         index_next = 0;
         len_captured_next = 0;
      end
      else
          state_next = state;
   end
   
   else if (state == `NOC2_STATE_WAITING_ACK_RST)
   begin
      noc_in_rdy = 1'b0;
      if (~msg_ack)
      begin
         state_next = `NOC2_STATE_IDLE;         
      end
      else
         state_next = state;
   end   
   
end
/*
always @ (posedge clk) begin
	if( msg_ack & msg_val) $display ("l15 n2 msg:%h", msg);
end
*/
endmodule
