`ifndef METRO_MPI_PKG
`define METRO_MPI_PKG
package metro_mpi_pkg;

    //HPM EVENTS
localparam 
    HPM_BRANCH_MISS=0,
    HPM_IS_BRANCH=1,
    HPM_BRANCH_TAKEN=2,
    HPM_EXE_STORE=3,
    HPM_EXE_LOAD=4,
    HPM_ICACHE_REQ=5,
    HPM_ICACHE_KILL=6,
    HPM_STALL_IF=7,
    HPM_STALL_ID=8,
    HPM_STALL_RR=9,
    HPM_STALL_EXE=10,
    HPM_STALL_WB=11,
    HPM_ICACHE_MISS_L2_HIT=12,
    HPM_ICACHE_MISS_KILL=13,
    HPM_ICACHE_BUSY=14,
    HPM_ICACHE_MISS_TIME=15,
    HPM_LOAD_STORE=16,
    HPM_DATA_DEPEND=17,
    HPM_STRUCT_DEPEND=18,
    HPM_GRAD_LIST_FULL=19,
    HPM_FREE_LIST_EMPTY=20,
    HPM_ITLB_ACCESS=21,
    HPM_ITLB_MISS=22,
    HPM_DTLB_ACCESS=23,
    HPM_DTLB_MISS=24,
    HPM_PTW_BUFFER_HIT=25,
    HPM_PTW_BUFFER_MISS=26,
    HPM_ITLB_STALL=27,
    HPM_DCACHE_STALL=28,
    HPM_DCACHE_STALL_REFILL=29,
    HPM_DCACHE_RTAB_ROLLBACK=30,
    HPM_DCACHE_REQ_ONHOLD=31,
    HPM_DCACHE_PREFETCH_REQ=32,
    HPM_DCACHE_READ_REQ=33,
    HPM_DCACHE_WRITE_REQ=34,
    HPM_DCACHE_CMO_REQ=35,
    HPM_DCACHE_UNCACHED_REQ=36,
    HPM_DCACHE_MISS_READ_REQ=37,
    HPM_DCACHE_MISS_WRITE_REQ=38,
    HPM_STALL_IR=39,
    HPM_L2_MISS=40,
    HPM_L2_ACCESS=41,
    HPM_L15_MISS=42,
    HPM_L15_ACCESS=43,
    HPM_ROI_CYCLES=44,
    HPM_DCACHE_WBF_WRITE=45,
    HPM_DCACHE_WBF_RDY=46,
    HPM_CNT_NUM = 47;

`ifdef PITON_PRONOC

    import pronoc_pkg_N1::*;
    import pronoc_pkg_N2::*;
    import pronoc_pkg_N3::*;
    
    typedef struct packed {    
        smartflit_chanel_t_N1  smartflit_chanel_N1;
        smartflit_chanel_t_N2  smartflit_chanel_N2;
        smartflit_chanel_t_N3  smartflit_chanel_N3;
    } noc_chanel_t;


    localparam CHIP_SET_ID = T1_N1*T2_N1*T3_N1+2*T1_N1; // endp connected  of west port of router 0-0
    localparam CHIP_SET_PORT = 3; //west port of first router

    localparam CONCENTRATION = T3_N1;

    typedef struct packed {    
        logic  [`PITON_NOC1_WIDTH-1:0] data1;
        logic  [`PITON_NOC2_WIDTH-1:0] data2;
        logic  [`PITON_NOC3_WIDTH-1:0] data3;
        logic  valid1,valid2,valid3;
        logic  yummy1,yummy2,yummy3;
    } op_chanel_t;

`else


    typedef struct packed {    
        logic  [`PITON_NOC1_WIDTH-1:0] data1;
        logic  [`PITON_NOC2_WIDTH-1:0] data2;
        logic  [`PITON_NOC3_WIDTH-1:0] data3;
        logic  [2:0] valid;
        logic  [2:0] yummy;        
    } noc_chanel_t;

    localparam CONCENTRATION = 1;
    localparam SMARTFLIT_CHANEL_w=1;
    localparam CHIP_SET_ID = 0; // endp connected  of west port of router 0-0
    localparam CHIP_SET_PORT = 3; //west port of first router
    localparam RAw=0;
    
    
`endif


localparam NOC_CHANEL_w = $bits(noc_chanel_t);     


localparam 
    PITON_EAST    =   0,
    PITON_NORTH   =   1, 
    PITON_WEST    =   2,
    PITON_SOUTH   =   3,
    PITON_P       =   4;   

localparam 
    PRONOC_LOCAL   =   0,
    PRONOC_EAST    =   1,
    PRONOC_NORTH   =   2, 
    PRONOC_WEST    =   3,
    PRONOC_SOUTH   =   4,
    PRONOC_P       =   5;


endpackage
`endif