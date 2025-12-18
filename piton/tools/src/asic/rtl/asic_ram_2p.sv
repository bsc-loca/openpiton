`ifdef PITON_ASIC_SYNTH
module asic_sram_2p #(
    parameter ADDR_WIDTH=1, 
    parameter DATA_WIDTH=1
) (
    input wire [ADDR_WIDTH-1  : 0]  AA,AB,
    input wire [DATA_WIDTH-1  : 0]  DB,
    input wire [DATA_WIDTH-1  : 0]  BWB,    
    input wire CLKA,CEA,
    input wire CLKB,CEB,
    output logic [DATA_WIDTH-1  : 0]  QA       
);   
    // Memory macros for dual port, 2P, ARM7FF technology: RF & SRAM
    // RF_2P_XX Two-Port High-Density Register File
    // SRAM_SP_XX Two-Port Ultra-High-Density SRAM
    // No Power_Pins
    // CENA, CENB: Read & Write Enables (active low)
    // WENB[]: Write Enable (active low, WENB[0]=LSB)
    `define ARM7FF_2P_INTERFACE(high,low) (\
            .CENA(~CEA), \
            .AA(AA), \
            .CENB(~CEB), \
            .AB(AB), \
            .DB(DB_tmp[high:low]), \
            .WENB(~BWB_tmp[high:low]), \
            .CLKA(CLKA), \
            .CLKB(CLKB), \
            .QA(QA_tmp[high:low]), \
            .STOV(1'b0), \
            .EMAA(3'b000), \
            .EMASA(1'b0), \
            .EMAB(3'b000), \
            .RET(1'b0), \
            .QNAPA(1'b0), \
            .QNAPB(1'b0));
    
    localparam DEPTH = 2 ** ADDR_WIDTH;
    generate
    
    if (  DATA_WIDTH <= 4)   begin : ram_reg
        // Internal memory array declaration
        typedef logic [DATA_WIDTH-1:0] mem_t [DEPTH];
        mem_t mem;
        // Process to update or read the memory array
        always_ff @(posedge CLKB) begin : mem_write_ff
            if (CEB == 1'b1) begin
                mem[AB] <= (mem[AB] & ~BWB) | (DB & BWB);
            end
        end : mem_write_ff

        always_ff @(posedge CLKA) begin : mem_read_ff
            if (CEA == 1'b1) begin
                QA <= mem[AA];
            end
        end : mem_read_ff
    end //ram_reg
    `ifdef SIMULATION
    else begin : ram_undef   //should not reach here at all 
        ASIC_2P_RAM_UNDEF  #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH))  UNDEF_RAM   `ARM7FF_2P_INTERFACE
    end
    `endif
    endgenerate
endmodule


module asic_sram_2p_reset #(
    parameter ADDR_WIDTH=1, 
    parameter DATA_WIDTH=1
) (
    input wire rst_n,
    input wire [ADDR_WIDTH-1  : 0]  AA,AB,
    input wire [DATA_WIDTH-1  : 0]  DB,
    input wire [DATA_WIDTH-1  : 0]  BWB,  // Bit enable, 1: write bit enable
    input wire CLKA,CEA,  // 1: read
    input wire CLKB,CEB,  // 1: write
    output wire [DATA_WIDTH-1  : 0]  QA
);   

// ----------------------------------------------------------------------------
// write_bypass on read/write collisions to the same address
// ----------------------------------------------------------------------------
wire                  read_write_collision;
reg                   read_write_collision_r;
reg  [DATA_WIDTH-1:0] mux_data_in_r;
reg  [DATA_WIDTH-1:0] mux_data_mask_in_r;
wire [DATA_WIDTH-1:0] tmp_QA;

// write_bypass on read/write collisions to the same address
//NOTE: keep bypassed data constant until a new read operation arrives!
always_ff @(posedge CLKA) begin
    if(!rst_n) begin
        read_write_collision_r <= 1'b0;
    end else begin
        if (read_write_collision) begin
            read_write_collision_r <= 1'b1;
            mux_data_in_r          <= DB;
            mux_data_mask_in_r     <= BWB;
        end else if (CEA) begin
            read_write_collision_r <= 1'b0;
        end
    end
end

// detect a read/write collision
// assign read_write_collision = (mux_rd_en && mux_wr_en && (mux_rd_addr == mux_wr_addr));
assign read_write_collision = (CEA && CEB && (AA == AB));

// generate the correct output in case of collision
//NOTE: assumes that tmp_QA (read data) is correct for the bits that are not being written
// assign data_out = read_write_collision_r ? ((QA & ~mux_data_mask_in_r) | (mux_data_in_r & mux_data_mask_in_r)) : QA;
assign QA = read_write_collision_r ? ((tmp_QA & ~mux_data_mask_in_r) | (mux_data_in_r & mux_data_mask_in_r)) : tmp_QA;
// ----------------------------------------------------------------------------

asic_sram_2p   #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))  the_ram (
    .AA(AA),
    .AB(AB),
    .DB(DB),
    .BWB(BWB),
    .CLKA(CLKA),
    .CEA(CEA),
    .CLKB(CLKB),
    .CEB(CEB),
    .QA(tmp_QA)
);

endmodule

`endif
