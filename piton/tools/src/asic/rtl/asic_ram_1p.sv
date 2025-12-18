/*****************************
*     asic_sram_1p
*
******************************/
`ifdef PITON_ASIC_SYNTH
module asic_sram_1p #(
    parameter ADDR_WIDTH=1, 
    parameter DATA_WIDTH=1
) (
    input wire  [ADDR_WIDTH-1  : 0]  A,
    input wire  [DATA_WIDTH-1  : 0]  DI,
    input wire  [DATA_WIDTH-1  : 0]  BW,
    input wire  CLK,CE, RDWEN,
    output logic [DATA_WIDTH-1  : 0]  DO
);   
    
    // Memory macros for Single Port ARM7FF technology: RF & SRAM
    // RF_SP_XX Single-Port High-Density Register File
    // SRAM_SP_XX Ultra-High-Density SRAM
    // No Power_Pins
    // CEN: Chip Enable (active low)
    // GWEN: Write Enable (active low)
    // WEN[]: Write Enable (active low, WEN[0]=LSB)
    // RET: Retention mode enable, active-HIGH
    // QNAP: Quick Nap mode enable, active-HIGH
    `define ARM7FF_SP_INTERFACE(high,low) ( \
            .A(A), \
            .D(DI_tmp[high:low]), \
            .CLK(CLK), \
            .CEN(~CE), \
            .GWEN(~RDWEN), \
            .WEN(~BW_tmp[high:low]), \
            .Q(DO_tmp[high:low]), \
            .EMA(3'b000), \
            .EMAW(2'b00), \
            .EMAS(1'b0), \
            .STOV(1'b0), \
            .RET(1'b0), \
            .QNAP(1'b0));
    localparam DEPTH = 2 ** ADDR_WIDTH;
    generate   
    if (  DATA_WIDTH <= 4)   begin : ram_reg
        // Internal memory array declaration
        typedef logic [DATA_WIDTH-1:0] mem_t [DEPTH];
        mem_t mem;
        // Process to update or read the memory array
        always_ff @(posedge CLK)
        begin : mem_update_ff
            if (CE == 1'b1) begin
            if (RDWEN == 1'b1) begin
                mem[A] <= (mem[A] & ~BW) | (DI & BW);
            end
            DO <= mem[A];
        end
        end : mem_update_ff
    end //ram_reg
    
    `ifdef SIMULATION
    else begin : ram_undef   //should not reach here at all 
        ASIC_2P_RAM_UNDEF  #(.DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH))  UNDEF_RAM   `ARM7FF_2P_INTERFACE(DATA_WIDTH-1,0)
    end
    `endif
    endgenerate
endmodule
`endif //PITON_ASIC_SYNTH
