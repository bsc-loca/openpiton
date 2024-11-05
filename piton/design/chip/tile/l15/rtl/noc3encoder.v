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
//  Filename      : noc3encoder.v
//  Created On    : 2014-02-05 20:06:27
//  Revision      :
//  Author        : Tri Nguyen
//  Company       : Princeton University
//  Email         : trin@princeton.edu
//
//  Description   :
//
//
//==================================================================================================
`include "l15.tmp.h"
`include "define.tmp.h"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none // DEFAULT_NETTYPE_NONE
`endif
module noc3encoder #(
    parameter L15_L1D_LINE_SIZE = 64
) (
    input wire clk,
    input wire rst_n,

    input wire l15_noc3encoder_req_val,
    input wire [`L15_NOC3_REQTYPE_WIDTH-1:0] l15_noc3encoder_req_type,
    input wire [(L15_L1D_LINE_SIZE*8)-1:0] l15_noc3encoder_req_data,
    input wire [`L15_MSHR_TYPE_WIDTH-1:0] l15_noc3encoder_req_mshr_type,
    input wire [`L15_THREADID_MASK] l15_noc3encoder_req_threadid,
    input wire [1:0] l15_noc3encoder_req_sequenceid,
    input wire [39:0] l15_noc3encoder_req_address,
    input wire l15_noc3encoder_req_with_data,
    // input wire l15_noc3encoder_req_fwdack_hit,
    input wire l15_noc3encoder_req_was_inval,
    input wire [3:0] l15_noc3encoder_req_fwdack_vector,
    input wire [`PACKET_HOME_ID_WIDTH-1:0] l15_noc3encoder_req_homeid,
    input wire [`NOC_CHIPID_WIDTH-1:0] chipid,
    input wire [`NOC_X_WIDTH-1:0] coreid_x,
    input wire [`NOC_Y_WIDTH-1:0] coreid_y,

    input wire noc3out_ready,

    output reg noc3encoder_l15_req_ack,

    output noc3encoder_noc3out_val,
    output [`PITON_NOC3_WIDTH-1:0] noc3encoder_noc3out_data
   );

localparam L15_MAX_DATA_PACKETS = L15_L1D_LINE_SIZE/`NOC_BYTES_WIDTH;

localparam 
    NOC_WIDTH = `PITON_NOC3_WIDTH,
    NOC3_WORDS_NUM = NOC_WIDTH /64;


reg [`PITON_NOC3_WIDTH-1:0] flit;
reg [`NOC3_FLIT_STATE_WIDTH-1:0] flit_state;
reg [`NOC3_FLIT_STATE_WIDTH-1:0] flit_state_next;

wire [`PHY_ADDR_WIDTH-1:0] address;
wire [`NOC_X_WIDTH-1:0] dest_l2_xpos;
wire [`NOC_Y_WIDTH-1:0] dest_l2_ypos;
wire [`NOC_CHIPID_WIDTH-1:0] dest_chipid;
wire [`NOC_FBITS_WIDTH-1:0] dest_fbits;
wire [`NOC_X_WIDTH-1:0] src_l2_xpos;
wire [`NOC_Y_WIDTH-1:0] src_l2_ypos;
wire [`NOC_CHIPID_WIDTH-1:0] src_chipid;
wire [`NOC_FBITS_WIDTH-1:0] src_fbits;
reg [`MSG_LENGTH_WIDTH-1:0] msg_length;
reg [`MSG_TYPE_WIDTH-1:0] msg_type;
wire [`MSG_MSHRID_WIDTH-1:0] msg_mshrid;
reg [`MSG_MESI_BITS-1:0] msg_mesi;
// reg [`MSG_SUBLINE_ID_WIDTH-1:0] msg_subline_id;
wire [`MSG_LAST_SUBLINE_WIDTH-1:0] msg_last_subline;
reg [`MSG_OPTIONS_1] msg_options_1;
reg [`MSG_OPTIONS_2_] msg_options_2;
reg [`MSG_OPTIONS_3_] msg_options_3;
reg [`MSG_OPTIONS_4] msg_options_4;
reg [`MSG_CACHE_TYPE_WIDTH-1:0] msg_cache_type;
reg [`MSG_SUBLINE_VECTOR_WIDTH-1:0] msg_subline_vector;
reg [`MSG_DATA_SIZE_WIDTH-1:0] msg_data_size;


wire is_request;
wire is_response;
// reg msg_last_subline;
wire [1:0] last_subcacheline_id;

reg send_done;
// 9/24/14: add buffer between dcache and output
localparam 
    BUFFER_WIDTH = 
    (`PITON_NOC3_WIDTH == 64  ) ?  1 :
    (`PITON_NOC3_WIDTH == 128 || L15_MAX_DATA_PACKETS <= 2 ) ?  2 : 
    (`PITON_NOC3_WIDTH == 256 || L15_MAX_DATA_PACKETS <= 4 ) ?  4 : 8 ,
    SUB_FLIT_WIDTH = (NOC3_WORDS_NUM<4)? 4 : NOC3_WORDS_NUM;

reg [63:0] l15_noc3encoder_req_data_f [0 : BUFFER_WIDTH-1]; // The buffer between dcache and output
wire [63 : 0] l15_noc3encoder_req_data_array [0 : L15_MAX_DATA_PACKETS-1];

wire  [`NOC3_FLIT_STATE_WIDTH-1:0] ptr; // point to where data flit should be captured from buffer
wire [`NOC3_FLIT_STATE_WIDTH-1:0] data_ptr = (is_response)? `NOC3_RES_DATA_1 :`NOC3_REQ_DATA_1 ; //point to where the data flit starts

wire sending_hdr = flit_state < data_ptr;
wire [`NOC3_FLIT_STATE_WIDTH-1:0] flit_state_incr;


assign ptr = (flit_state_next > data_ptr) ? flit_state_next - data_ptr : 0;

/*
always @ (posedge clk)    begin
    if (!rst_n) ptr <= 0;
    else begin  
        if (l15_noc3encoder_req_val ) begin
            if(send_done) ptr <= 0;
            else
                if(flit_state_next < data_ptr )   ptr<= (flit_state_next > data_ptr) ? flit_state_next - data_ptr : 0;
                else ptr<=ptr + NOC3_WORDS_NUM;                      
        end
    end//else
end //always
*/

genvar i;
generate 
    for (i=0; i< L15_MAX_DATA_PACKETS; i=i+1) begin : sep 
        assign l15_noc3encoder_req_data_array [i] = l15_noc3encoder_req_data [(i+1)*64-1 : i*64];
    end
    for (i=0; i<BUFFER_WIDTH; i=i+1) begin : buff
         always @ (posedge clk)    begin
              if (!rst_n) l15_noc3encoder_req_data_f [i] <= 0;
              else begin  
                 if(ptr < L15_MAX_DATA_PACKETS-i ) l15_noc3encoder_req_data_f [i] <= l15_noc3encoder_req_data_array[ptr + i ];
                        
              end//else
           end //always
    end
endgenerate




reg [63:0] sub_flit [SUB_FLIT_WIDTH-1 : 0];
integer ii;

always @ (*) begin
    // so that the flit is not a latch
    sub_flit[0]=64'd0; 
    sub_flit[1]=64'd0;   
    sub_flit[2]=64'd0;   
  
   if(is_request) begin 
        sub_flit[0][`MSG_DST_CHIPID] = dest_chipid;
        sub_flit[0][`MSG_DST_X] = dest_l2_xpos;
        sub_flit[0][`MSG_DST_Y] = dest_l2_ypos;
        sub_flit[0][`MSG_DST_FBITS] = dest_fbits;
        sub_flit[0][`MSG_LENGTH] = msg_length;
        sub_flit[0][`MSG_TYPE] = msg_type;
        sub_flit[0][`MSG_MSHRID] = msg_mshrid;
        sub_flit[0][`MSG_OPTIONS_1] = msg_options_1;    
        
        if (msg_length > 0) begin 
            sub_flit[1][`MSG_ADDR_] = address;
            sub_flit[1][`MSG_OPTIONS_2_] = msg_options_2;
        end
    
        if (msg_length > 1) begin       
            sub_flit[2][`MSG_SRC_CHIPID_] = src_chipid;
            sub_flit[2][`MSG_SRC_X_] = src_l2_xpos;
            sub_flit[2][`MSG_SRC_Y_] = src_l2_ypos;
            sub_flit[2][`MSG_SRC_FBITS_] = src_fbits;
            sub_flit[2][`MSG_OPTIONS_3_] = msg_options_3;
        end
   end else begin 
        sub_flit[0][`MSG_DST_CHIPID] = dest_chipid;
        sub_flit[0][`MSG_DST_X] = dest_l2_xpos;
        sub_flit[0][`MSG_DST_Y] = dest_l2_ypos;
        sub_flit[0][`MSG_DST_FBITS] = dest_fbits;
        sub_flit[0][`MSG_LENGTH] = msg_length;
        sub_flit[0][`MSG_TYPE] = msg_type;
        sub_flit[0][`MSG_MSHRID] = msg_mshrid;
        sub_flit[0][`MSG_OPTIONS_4] = msg_options_4;


        if (msg_length > 0)sub_flit[1][`NOC_DATA_WIDTH-1:0] = l15_noc3encoder_req_data_f [0];

        if (msg_length > 1)sub_flit[2][`NOC_DATA_WIDTH-1:0] = l15_noc3encoder_req_data_f [1];
    end
    
    for (ii=3;ii< SUB_FLIT_WIDTH; ii=ii+1) begin : lp2
        sub_flit[ii]=64'd0; 
        if (msg_length > ii-1) sub_flit[ii][`NOC_DATA_WIDTH-1:0] = l15_noc3encoder_req_data_f[(ii-3) % BUFFER_WIDTH]; 
    end //for    
end

reg  delay, delay_next; // incase data is gona be send via first flit we need one cycle delay for buffer updating
wire stall;

generate 
for (i=0; i< NOC3_WORDS_NUM; i=i+1) begin 
    always @ (*) begin
       flit [(i+1)*64-1 : i*64] = 0;
       if(sending_hdr) flit [(i+1)*64-1 : i*64] = sub_flit[flit_state + i];
       else flit [(i+1)*64-1 : i*64] = l15_noc3encoder_req_data_f[i]; 
    end       
end


if(NOC_WIDTH == 64) begin : W64

    assign flit_state_incr = flit_state + 1;
    always @ (*) begin        
          send_done =    (flit_state ==  msg_length);
          
    end
    assign stall = 1'b0;
end else begin : NOT_W64
      // need to wait one-cycle for data pipe register
      always @(posedge clk) begin 
        if(!rst_n)delay<=1'b0;
        delay <=delay_next;
      end

      assign flit_state_incr =  flit_state + NOC3_WORDS_NUM;

      always @ (*) begin        
         delay_next = 1'b0;
         send_done =    (msg_length < flit_state  +  NOC3_WORDS_NUM); 
         if (l15_noc3encoder_req_val == 1'b1 && flit_state == 0 &&  NOC3_WORDS_NUM > data_ptr ) begin
            delay_next = 1'b1;
         end
      end
      
      assign stall =(l15_noc3encoder_req_val == 1'b1 && flit_state == 0 &&  NOC3_WORDS_NUM > data_ptr )? ~delay  : 1'b0;

end 
endgenerate



always @ (posedge clk)
begin
    if (!rst_n)
    begin
        flit_state <= 0;
    end
    else
    begin
        flit_state <= flit_state_next;
    end
end


assign is_request = (l15_noc3encoder_req_type == `L15_NOC3_REQTYPE_WRITEBACK);
assign is_response = !is_request;
assign dest_chipid = l15_noc3encoder_req_homeid[`PACKET_HOME_ID_CHIP_MASK];
assign address = l15_noc3encoder_req_address;
assign dest_l2_xpos = l15_noc3encoder_req_homeid[`PACKET_HOME_ID_X_MASK];
assign dest_l2_ypos = l15_noc3encoder_req_homeid[`PACKET_HOME_ID_Y_MASK];
assign dest_fbits = `NOC_FBITS_L2;
assign msg_mshrid = {l15_noc3encoder_req_threadid, l15_noc3encoder_req_mshr_type};

assign src_l2_xpos = coreid_x;
assign src_l2_ypos = coreid_y;
assign src_chipid = chipid;
assign src_fbits = `NOC_FBITS_L1;

assign last_subcacheline_id =  (l15_noc3encoder_req_fwdack_vector[3] == 1'b1) ? 2'b11 :
                            (l15_noc3encoder_req_fwdack_vector[2] == 1'b1) ? 2'b10 :
                            (l15_noc3encoder_req_fwdack_vector[1] == 1'b1) ? 2'b01 :
                                                                             2'b00 ;
assign  msg_last_subline = last_subcacheline_id == l15_noc3encoder_req_sequenceid;
assign  noc3encoder_noc3out_val = l15_noc3encoder_req_val & ~stall;
assign  noc3encoder_noc3out_data = flit;

always @ (*)begin 
    msg_options_1 = 0;
    msg_options_2 = 0;
    msg_options_3 = 0;
    msg_options_4 = 0;

    // trin: line coverage: 16B transaction apparently does not happen with the T1 core
    msg_options_2[`MSG_DATA_SIZE_] = msg_data_size;
    msg_options_2[`MSG_CACHE_TYPE_] = msg_cache_type;
    msg_options_2[`MSG_SUBLINE_VECTOR_] = msg_subline_vector;

    msg_options_4[`MSG_LAST_SUBLINE] = msg_last_subline || (l15_noc3encoder_req_type == `L15_NOC3_REQTYPE_ICACHE_INVAL_ACK);
    msg_options_4[`MSG_SUBLINE_ID] = l15_noc3encoder_req_sequenceid;

end



always @ *
begin    

    msg_length = 0;
    msg_type = 0;    
    msg_mesi = 0;
    // msg_l2_miss = 0;
    // msg_subline_id = 0;
    msg_cache_type = 0;
    msg_subline_vector = 0; // always 0 for requests
    msg_data_size = 0;
    

    case (l15_noc3encoder_req_type)
        `L15_NOC3_REQTYPE_WRITEBACK:
        begin
            // specify address (should be specified by default)
            msg_type = `MSG_TYPE_WB_REQ;
            msg_length = 2+L15_MAX_DATA_PACKETS; // 2 extra req headers + 8 data (512b=64*8)
            // msg_cache_type = `MSG_CACHE_TYPE_DATA;
        end
        `L15_NOC3_REQTYPE_DOWNGRADE_ACK:
        begin
            msg_type = `MSG_TYPE_LOAD_FWDACK;
            if (l15_noc3encoder_req_with_data)
            begin
                msg_length = 2;
                msg_data_size = `MSG_DATA_SIZE_32B;
            end
            else
                msg_length = 0;
        end
        `L15_NOC3_REQTYPE_INVAL_ACK:
        begin
            // specify sequence id + if is last
            if (l15_noc3encoder_req_was_inval)
               msg_type = `MSG_TYPE_INV_FWDACK;
            else
               msg_type = `MSG_TYPE_STORE_FWDACK;
           
            if (l15_noc3encoder_req_with_data)
            begin
                msg_length = 2;
                msg_data_size = `MSG_DATA_SIZE_32B;
            end
            else
                msg_length = 0;
        end
        `L15_NOC3_REQTYPE_ICACHE_INVAL_ACK:
        begin
            // specify sequence id + if is last
            msg_type = `MSG_TYPE_INV_FWDACK;
            msg_length = 0;
        end
        default: begin 
            msg_length = 0;
            msg_type = 0;
        end
    endcase

    
    // does not need to specify cache line state
    // no l2miss


   

    

    // next flit state logic
    flit_state_next = flit_state;
    if (l15_noc3encoder_req_val & ~stall)
    begin
            if (noc3out_ready)
            begin
                if (~send_done)
                    flit_state_next = flit_state_incr;  
                else
                    flit_state_next = `NOC1_REQ_HEADER_1;
            end
            else
                flit_state_next = flit_state;
    end
    else
        if(~stall) flit_state_next = `NOC1_REQ_HEADER_1;

    // ack logic to L2
    if (l15_noc3encoder_req_val && send_done==1'b1 && noc3out_ready && stall == 1'b0)
        noc3encoder_l15_req_ack = 1'b1;
    else
        noc3encoder_l15_req_ack = 1'b0;
end
endmodule
