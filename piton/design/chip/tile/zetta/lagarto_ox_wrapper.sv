/*
 *  Authors       : Oscar Lostes Cazorla, Noelia Oliete Escuin
 *  Creation Date : July, 2023
 *  Description   : Lagarto Ox Wrapper to be used in OpenPiton
 *  History      :
 */
`include "l15.tmp.h"
`include "hpdcache_typedef.svh"
 module lagarto_ox_wrapper
    import wt_cache_pkg::*;
 #(
    parameter int   ADDR_SIZE = 40,               //! Address size: max between Virtual Address size and Physical Address Size.
    
    
    // PMA regions
    // IO addresses
    parameter int unsigned                                  NIOSections    =  1,
    parameter logic [NIOSections-1:0][ADDR_SIZE-1:0]        InitIOBase  = 40'hC0000000,
    parameter logic [NIOSections-1:0][ADDR_SIZE-1:0]        InitIOEnd   = 40'hFFFFFFFF,
    // Mapped addresses (IO and cached)
    parameter int unsigned                                  NMappedSections       =  1,
    parameter logic [NMappedSections-1:0][ADDR_SIZE-1:0]    InitMappedBase  = 40'hC0000000,
    parameter logic [NMappedSections-1:0][ADDR_SIZE-1:0]    InitMappedEnd   = 40'hFFFFFFFF,
    // BROM address
    parameter logic [ADDR_SIZE-1:0]                         InitBROMBase  = 40'hC0000000,
    parameter logic [ADDR_SIZE-1:0]                         InitBROMEnd   = 40'hFFFFFFFF,
    parameter logic [ADDR_SIZE-1:0]                         InitDMBase    = 40'h4011_0000,

    parameter int                                   NC_MEM_DATA_SIZE        = 64,

    parameter int                                   ICACHE_FETCH_WIDTH      = 256,
    parameter int                                   ASID_SIZE               = 7,

    // HPDC Parameters
    parameter int                                   MEM_DATA_SIZE         = 512,
    parameter int                                   MEM_ID_SIZE           = 8,
    parameter int                                   DCACHE_NUM_SETS       = 128,
    parameter int                                   DCACHE_NUM_WAYS       = 4,
    parameter int                                   DCACHE_LINE_WIDTH     = 512,
    parameter int                                   DCACHE_MSHR_SETS      = 32,
    parameter int                                   DCACHE_MSHR_WAYS      = 2,
    parameter int                                   DCACHE_WBUF_SIZE      = 8,
    parameter int                                   DCACHE_WT_NOT_WB      = 1,
    parameter logic                                 DCACHE_EN_TRANS       = 1'b1,
    parameter int                                   DCACHE_INFLIGHT_OPS   = DCACHE_MSHR_SETS * DCACHE_MSHR_WAYS,

    parameter logic                                 WR_COALESCING_EN      = 0,
    parameter logic [$clog2(DCACHE_WBUF_SIZE)-1:0]  WR_COALESCING_TH      = 4,

    // HPDC Memory Interface Parameters
    localparam type                                  hpdcache_mem_addr_t   = logic[ADDR_SIZE-1:0],
    localparam type                                  hpdcache_mem_id_t     = logic[MEM_ID_SIZE-1:0],
    localparam type                                  hpdcache_mem_data_t   = logic[MEM_DATA_SIZE-1:0],
    localparam type                                  hpdcache_mem_be_t     = logic[(MEM_DATA_SIZE/8)-1:0],

    localparam type                                  hpdcache_mem_req_t    = `HPDCACHE_DECL_MEM_REQ_T(hpdcache_mem_addr_t, hpdcache_mem_id_t),
    localparam type                                  hpdcache_mem_resp_r_t = `HPDCACHE_DECL_MEM_RESP_R_T(hpdcache_mem_id_t, hpdcache_mem_data_t),
    localparam type                                  hpdcache_mem_req_w_t  = `HPDCACHE_DECL_MEM_REQ_W_T(hpdcache_mem_data_t, hpdcache_mem_be_t),
    localparam type                                  hpdcache_mem_resp_w_t = `HPDCACHE_DECL_MEM_RESP_W_T(hpdcache_mem_id_t),

    localparam type                                  hpdcache_nline_t      = logic[ADDR_SIZE-$clog2(DCACHE_LINE_WIDTH/8)-1:0],

    localparam int                                   ICACHE_IDX_BITS_SIZE    = 12,
    localparam int                                   ICACHE_VPN_BITS_SIZE    = ADDR_SIZE - ICACHE_IDX_BITS_SIZE,
    
    localparam int DEBUG_PHY_REGS_SIZE                  = 9,
    localparam int XLEN                                 = 64,
    localparam int LOG_REGS                             = 66,
    localparam int PHY_REGS                             = 512,
    localparam int TOTAL_LOG_REGS_BITS                  = $clog2(LOG_REGS),
    localparam int TOTAL_PHY_REGS_BITS                  = $clog2(PHY_REGS)
)
(
    `ifdef INTEL_PHYSICAL_MEM_CTRL
    input  logic [27:0] hduspsr_mem_ctrl,
    input  logic [27:0] uhdusplr_mem_ctrl,
    `endif
    input  logic                                    clk_i,
    input  logic                                    reset_l,     // This is an openpiton-specific name, do not change (hier. paths in TB use this)
    input  logic [ADDR_SIZE-1:0]                    boot_addr_i, //! On boot, address to use by the CSR's MTVEC.
    input  logic [63:0]                             hart_id_i,
    `ifdef PITON_CINCORANCH
    input  logic [1:0]                              boot_main_id_i,
    `endif  // Custom for CincoRanch
    `ifdef EXTERNAL_HPM_EVENT_NUM
    input  logic [`EXTERNAL_HPM_EVENT_NUM-1:0]      external_hpm_i,
    `endif
    output logic [$size(l15_req_t)-1:0]             l15_req_o,
    input  logic [$size(l15_rtrn_t)-1:0]            l15_rtrn_i,
    `ifdef INTEL_FSCAN_CTECH
    input  logic                               fscan_rstbypen,
    `endif

//------------------------------------------------------------------------------------
// Interface with the Debug Module
//------------------------------------------------------------------------------------
    input logic                            debug_contr_hart_reset_i,
    input logic                            debug_contr_halt_req_i,
    input logic                            debug_contr_resume_req_i,
    input logic                            debug_contr_progbuf_req_i,
    input logic                            debug_contr_halt_on_reset_i,

    input logic                            debug_reg_rnm_read_en_i,
    input logic  [TOTAL_LOG_REGS_BITS-1:0] debug_reg_rnm_read_reg_i,
    input logic                            debug_reg_rf_en_i,
    input logic  [TOTAL_PHY_REGS_BITS-1:0] debug_reg_rf_preg_i,
    input logic                            debug_reg_rf_we_i,
    input logic                 [XLEN-1:0] debug_reg_rf_wdata_i,

    output logic                           debug_contr_halt_ack_o,
    output logic                           debug_contr_halted_o,
    output logic                           debug_contr_resume_ack_o,
    output logic                           debug_contr_running_o,
    output logic                           debug_contr_progbuf_ack_o,
    output logic                           debug_contr_parked_o,
    output logic                           debug_contr_unavail_o,
    output logic                           debug_contr_progbuf_xcpt_o,
    output logic                           debug_contr_havereset_o,

    output logic [TOTAL_PHY_REGS_BITS-1:0] debug_reg_rnm_read_resp_o,
    output logic                [XLEN-1:0] debug_reg_rf_rdata_o,

    input logic time_irq_i,
    input logic [63:0] time_i,
    input logic [1:0]  irq_i,
    input logic soft_irq_i

    //output logic       visa_dp_ifu_deco_wr_o,     //! VISA: Any instruction ready from fetch
    //output logic       visa_dp_ifu_deco_grant_o,  //! VISA: Any instruction progressing from fetch
    //output logic       visa_dp_rnm_bke_wr_o,      //! VISA: Any instruction ready from rename
    //output logic       visa_dp_rnm_bke_grant_o,   //! VISA: Any instruction progression into backend
    //output logic       visa_dp_disp_barrier_o,    //! VISA: Any instruction dispatching into barrier
    //output logic       visa_dp_disp_integer_o,    //! VISA: Any instruction dispatching into integer queue
    //output logic       visa_dp_disp_fp_o,         //! VISA: Any instruction dispatching into fp queue
    //output logic       visa_dp_disp_mem_o,        //! VISA: Any instruction dispatching into mem queue
    //output logic       visa_dp_commit_o,          //! VISA: Any instruction commiting
    //output logic       visa_dcache_resp_valid_o,  //! VISA: Any response from dcache
    //output logic       visa_icache_resp_valid_o,  //! VISA: Any response from imem
    //output logic       visa_event_vm_enable_o,    //! VISA: Virtual memory enabled
    //output logic       visa_event_interrupt_o,    //! VISA: Handling an interrupt
    //output logic       visa_event_exception_o,    //! VISA: Handling an exception
    //output logic [1:0] visa_event_csr_priv_lvl_o  //! VISA: CSR privilege level
);


// icache wires
logic                             l1_request_valid;
logic                             l1_request_nc;
hpdcache_mem_addr_t               l1_request_nc_addr;
logic                             l2_response_valid;
hpdcache_mem_addr_t               l1_request_paddr;
hpdcache_mem_data_t               l2_response_data;
logic [1:0]                       l2_response_seqnum = '0;
logic                             l2_inval_request;
hpdcache_mem_addr_t               l2_inval_addr;

//      Miss read interface
logic                             mem_req_read_ready;
logic                             mem_req_read_valid;
hpdcache_mem_req_t                mem_req_read;

logic                             mem_resp_read_ready;
logic                             mem_resp_read_valid;
hpdcache_mem_resp_r_t             mem_resp_read;

//      Write-buffer write interface
logic                             mem_req_write_ready;
logic                             mem_req_write_valid;
hpdcache_mem_req_t                mem_req_write;

logic                             mem_req_write_data_ready;
logic                             mem_req_write_data_valid;
hpdcache_mem_req_w_t              mem_req_write_data;

logic                             mem_resp_write_ready;
logic                             mem_resp_write_valid;
hpdcache_mem_resp_w_t             mem_resp_write;

logic                             mem_inval_valid;
hpdcache_nline_t                  mem_inval;

logic [15:0] wake_up_cnt_d, wake_up_cnt_q;
logic rst_n;

assign wake_up_cnt_d = (wake_up_cnt_q[$high(wake_up_cnt_q)]) ? wake_up_cnt_q : wake_up_cnt_q + 1;

always_ff @(posedge clk_i or negedge reset_l) begin : p_regs
    if(~reset_l) begin
        wake_up_cnt_q <= 0;
    end else begin
        wake_up_cnt_q <= wake_up_cnt_d;
    end
end

// reset gate this
`ifdef INTEL_FSCAN_CTECH
wire rst_n_wire;

assign rst_n_wire = wake_up_cnt_q[$high(wake_up_cnt_q)] & reset_l;

ctech_lib_mux_2to1 lagarto_ox_top_reset_mux (.d1(reset_l),.d2(rst_n_wire),.s(fscan_rstbypen),.o(rst_n));
`else // INTEL_FSCAN_CTECH
assign rst_n = wake_up_cnt_q[$high(wake_up_cnt_q)] & reset_l;
`endif // INTEL_FSCAN_CTECH

lagarto_ox_top #(
    .CORE_SYSTEM_DIRECT_RSTN                (1'b1), // OpenPiton already provides a synchronizer, use direct reset and do not instantiate one inside ox
    .N_IO_SECTIONS                          (NIOSections),
    .INIT_IO_BASE                           (InitIOBase),
    .INIT_IO_END                            (InitIOEnd),
    .N_MAPPED_SECTIONS                      (NMappedSections),
    .INIT_MAPPED_BASE                       (InitMappedBase),
    .INIT_MAPPED_END                        (InitMappedEnd),
    
    // Debug Module program buffer address
    .PROGRAM_BUFFER_ADDR                    (InitDMBase),
    
    // global cacheable/non-cacheable data sizes
    .MEM_DATA_SIZE                          (MEM_DATA_SIZE),
    .MEM_ID_SIZE                            (MEM_ID_SIZE),
    .NC_MEM_DATA_SIZE                       (NC_MEM_DATA_SIZE),

    .ADDR_SIZE                              (ADDR_SIZE),

    // Icache params
    .REG_ICACHE_RESP                        (0),
    .ICACHE_ITLB_CYCLE                      (1),
    .ICACHELINE_SIZE                        (ICACHE_FETCH_WIDTH),
    .ICACHE_IDX_BITS_SIZE                   (ICACHE_IDX_BITS_SIZE),
    .ICACHE_VPN_BITS_SIZE                   (ICACHE_VPN_BITS_SIZE),
    .ASID_SIZE                              (ASID_SIZE),


    // HPDCache parameters
    .WR_COALESCING_EN                       (WR_COALESCING_EN),
    .WR_COALESCING_TH                       (WR_COALESCING_TH),
    .DCACHE_EN_TRANS                        (DCACHE_EN_TRANS),
    .DCACHE_INFLIGHT_OPS                    (DCACHE_INFLIGHT_OPS),
    .DCACHE_NUM_SETS                        (DCACHE_NUM_SETS),
    .DCACHE_NUM_WAYS                        (DCACHE_NUM_WAYS),
    .DCACHE_LINE_WIDTH                      (DCACHE_LINE_WIDTH),
    .DCACHE_MSHR_SETS                       (DCACHE_MSHR_SETS),
    .DCACHE_MSHR_WAYS                       (DCACHE_MSHR_WAYS),
    .DCACHE_WBUF_SIZE                       (DCACHE_WBUF_SIZE),
    .DCACHE_WT_NOT_WB                       (DCACHE_WT_NOT_WB),
    
    // HPDCache memory intf params
    .hpdcache_mem_addr_t                    (hpdcache_mem_addr_t),
    .hpdcache_mem_id_t                      (hpdcache_mem_id_t),
    .hpdcache_mem_data_t                    (hpdcache_mem_data_t),
    .hpdcache_mem_be_t                      (hpdcache_mem_be_t),

    .hpdcache_mem_req_t                     (hpdcache_mem_req_t),
    .hpdcache_mem_resp_r_t                  (hpdcache_mem_resp_r_t),
    .hpdcache_mem_req_w_t                   (hpdcache_mem_req_w_t),
    .hpdcache_mem_resp_w_t                  (hpdcache_mem_resp_w_t)
) core_inst (
    `ifdef INTEL_PHYSICAL_MEM_CTRL
    .hduspsr_mem_ctrl                       (hduspsr_mem_ctrl),
    .uhdusplr_mem_ctrl                      (uhdusplr_mem_ctrl),
    `endif
    .clk_i                                  (clk_i),
    .rstn_i                                 (rst_n),
    .reset_addr_i                           (boot_addr_i),
    .core_id_i                              (hart_id_i),

    // Debug module
    .debug_running_o                        (debug_contr_running_o),
    .debug_parked_o                         (debug_contr_parked_o),
    .debug_havereset_o                      (debug_contr_havereset_o),
    .debug_unavail_o                        (debug_contr_unavail_o),
    .debug_hart_reset_i                     (debug_contr_hart_reset_i),


    .debug_rnm_read_en_i                    (debug_reg_rnm_read_en_i),
    .debug_rnm_read_reg_i                   (debug_reg_rnm_read_reg_i),
    .debug_rnm_read_resp_o                  (debug_reg_rnm_read_resp_o),

    .debug_rf_en_i                          (debug_reg_rf_en_i),
    .debug_rf_preg_i                        (debug_reg_rf_preg_i),
    .debug_rf_rdata_o                       (debug_reg_rf_rdata_o),

    .debug_rf_we_i                          (debug_reg_rf_we_i),
    .debug_rf_wdata_i                       (debug_reg_rf_wdata_i),

    .debug_resume_req_i                     (debug_contr_resume_req_i),
    .debug_resume_ack_o                     (debug_contr_resume_ack_o),

    .debug_halt_req_i                       (debug_contr_halt_req_i),
    .debug_halt_ack_o                       (debug_contr_halt_ack_o),
    .debug_halt_on_reset_i                  (debug_contr_halt_on_reset_i),
    .debug_halted_o                         (debug_contr_halted_o),

    .debug_progbuf_run_req_i                (debug_contr_progbuf_req_i),
    .debug_progbuf_run_ack_o                (debug_contr_progbuf_ack_o),
    .debug_progbuf_xcpt_o                   (debug_contr_progbuf_xcpt_o),

`ifdef PITON_CINCORANCH
    .boot_main_id_i                         (boot_main_id_i),
`endif  // Custom for CincoRanch
 `ifdef EXTERNAL_HPM_EVENT_NUM
    .external_hpm_i                         (external_hpm_i),
 `endif

    .io_mem_acquire_nc_o                    (l1_request_nc),
    .io_mem_acquire_nc_addr_o               (l1_request_nc_addr),

    .io_mem_acquire_valid_o                 (l1_request_valid),
    .io_mem_acquire_bits_addr_block_o       (l1_request_paddr),
    .io_mem_grant_valid_i                   (l2_response_valid),
    .io_mem_grant_bits_data_i               (l2_response_data),
    .io_mem_grant_bits_addr_beat_i          (l2_response_seqnum),
    .io_mem_grant_inval_i                   (l2_inval_request),
    .io_mem_grant_inval_addr_i              (l2_inval_addr),

    .mem_req_read_ready_i                   (mem_req_read_ready),
    .mem_req_read_valid_o                   (mem_req_read_valid),
    .mem_req_read_o                         (mem_req_read),

    .mem_resp_read_ready_o                  (mem_resp_read_ready),
    .mem_resp_read_valid_i                  (mem_resp_read_valid),
    .mem_resp_read_i                        (mem_resp_read),


    .mem_req_write_ready_i                  (mem_req_write_ready),
    .mem_req_write_valid_o                  (mem_req_write_valid),
    .mem_req_write_o                        (mem_req_write),

    .mem_req_write_data_ready_i             (mem_req_write_data_ready),
    .mem_req_write_data_valid_o             (mem_req_write_data_valid),
    .mem_req_write_data_o                   (mem_req_write_data),

    .mem_resp_write_ready_o                 (mem_resp_write_ready),
    .mem_resp_write_valid_i                 (mem_resp_write_valid),
    .mem_resp_write_i                       (mem_resp_write),

    .mem_inval_valid_i                      (mem_inval_valid),
    .mem_inval_i                            (mem_inval),


    .time_irq_i                             (time_irq_i),
    .eirq_i                                 (irq_i),
    .soft_irq_i                             (soft_irq_i),
    .time_i                                 (time_i),

    .visa_dp_ifu_deco_wr_o                  (),
    .visa_dp_ifu_deco_grant_o               (),
    .visa_dp_rnm_bke_wr_o                   (),
    .visa_dp_rnm_bke_grant_o                (),
    .visa_dp_disp_barrier_o                 (),
    .visa_dp_disp_o                         (),
    .visa_dp_issue_o                        (),
    .visa_dp_cmplt_o                        (),
    .visa_dp_commit_o                       (),
    .visa_dcache_resp_valid_o               (),
    .visa_icache_resp_valid_o               (),
    .visa_event_vm_enable_o                 (),
    .visa_event_interrupt_o                 (),
    .visa_event_exception_o                 (),
    .visa_event_csr_priv_lvl_o              ()
);


localparam NUM_PORTS_ADAPTER = 4;
localparam NUM_PORTS_ADAPTER_WIDTH = $clog2(NUM_PORTS_ADAPTER);
// Adapter HPDC-L1.5 Request Ports type
// 0: Maximum priority
// NUM_PORTS_ADAPTER - 1 : Less priority
localparam [NUM_PORTS_ADAPTER_WIDTH-1:0] ICACHE_PORT            = 0;
localparam [NUM_PORTS_ADAPTER_WIDTH-1:0] DCACHE_READ_PORT       = 1;
localparam [NUM_PORTS_ADAPTER_WIDTH-1:0] DCACHE_WRITE_PORT      = 2;
localparam [NUM_PORTS_ADAPTER_WIDTH-1:0] DCACHE_AMO_PORT        = 3;

typedef logic [NUM_PORTS_ADAPTER_WIDTH-1:0] req_portid_t;


cinco_ranch_hpdcache_subsystem_l15_adapter #(
    .CacheLineWidth               (DCACHE_LINE_WIDTH),
    .SwapEndianess                (1),
    .AddrWidth                   (ADDR_SIZE),
    .NumPorts                     (NUM_PORTS_ADAPTER),
    .IcachePort                   (ICACHE_PORT),
    .DcacheReadPort               (DCACHE_READ_PORT),
    .DcacheWritePort              (DCACHE_WRITE_PORT),
    .DcacheAmoPort                (DCACHE_AMO_PORT),
    .IcacheMemDataWidth           (MEM_DATA_SIZE), //L1I cacheline
    .HPDcacheMemDataWidth         (MEM_DATA_SIZE), //L1D cacheline
    .IcacheNoCachableSize         (`MSG_DATA_SIZE_8B), // 64b
    .WriteCoalescingEn            (WR_COALESCING_EN),
    .hpdcache_mem_req_t           (hpdcache_mem_req_t),
    .hpdcache_mem_req_w_t         (hpdcache_mem_req_w_t),
    .hpdcache_mem_resp_r_t        (hpdcache_mem_resp_r_t),
    .hpdcache_mem_resp_w_t        (hpdcache_mem_resp_w_t),
    .hpdcache_mem_id_t            (hpdcache_mem_id_t),
    .hpdcache_mem_addr_t          (hpdcache_mem_addr_t),
    .hpdcache_nline_t             (hpdcache_nline_t),
    .req_portid_t                 (req_portid_t)
) l15_adapter_inst (

    .clk_i                        (clk_i),
    .rst_ni                       (reset_l),

    //  Interfaces from/to I$
    .icache_miss_valid_i          (l1_request_valid),
    .icache_miss_ready_o          (),
    .icache_miss_paddr_i          (l1_request_paddr),

    .icache_miss_resp_valid_o     (l2_response_valid),
    .icache_miss_resp_data_o      (l2_response_data),
    .icache_inval_valid_o         (l2_inval_request),
    .icache_inval_addr_o          (l2_inval_addr),
    .brom_req_valid_i             (l1_request_nc),
    .brom_req_address_i           (l1_request_nc_addr),

    //  Interfaces from/to D$
    //      Miss-read interface
    .dcache_read_ready_o          (mem_req_read_ready),
    .dcache_read_valid_i          (mem_req_read_valid),
    .dcache_read_i                (mem_req_read),

    .dcache_read_resp_ready_i     (mem_resp_read_ready),
    .dcache_read_resp_valid_o     (mem_resp_read_valid),
    .dcache_read_resp_o           (mem_resp_read),

    // Invalidation interface
    .dcache_inval_valid_o         (mem_inval_valid),
    .dcache_inval_o               (mem_inval),

    //      Write-buffer write interface
    .dcache_write_ready_o         (mem_req_write_ready),
    .dcache_write_valid_i         (mem_req_write_valid),
    .dcache_write_i               (mem_req_write),

    .dcache_write_data_ready_o    (mem_req_write_data_ready),
    .dcache_write_data_valid_i    (mem_req_write_data_valid),
    .dcache_write_data_i          (mem_req_write_data),

    .dcache_write_resp_ready_i    (mem_resp_write_ready),
    .dcache_write_resp_valid_o    (mem_resp_write_valid),
    .dcache_write_resp_o          (mem_resp_write),

    //    Ports to/from L1.5
    .l15_req_o                    (l15_req_o),
    .l15_rtrn_i                   (l15_rtrn_i)
);

 endmodule : lagarto_ox_wrapper
