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

#include "Vmetro_tile.h"
#include "verilated.h"
#include <iostream>

#include "mcs_map_info.tmp.h"
#include "metro_mpi.h"

//#define VERILATOR_VCD 0

//#define KONATA_EN

//#define REPORT_RANKS


#ifdef VERILATOR_VCD
#include "verilated_vcd_c.h"
#endif
#include <iomanip>

#ifdef KONATA_EN
#include "dpi_konata.h"
#endif



uint64_t main_time = 0; // Current simulation time
uint64_t clk = 0;
Vmetro_tile* top;
int mpi_rank, dest, mpi_size;
int rankN, rankS, rankW, rankE;
int tile_x, tile_y;//, PITON_X_TILES, PITON_Y_TILES;
int smart_max=0;




#define RANK_NUM 4
int MY_RANK [RANK_NUM];

#define EAST       0
#define NORTH      1
#define WEST       2
#define SOUTH      3


#ifdef VERILATOR_VCD
VerilatedVcdC* tfp;
#endif
// This is a 64-bit integer to reduce wrap over issues and
// // allow modulus. You can also use a double, if you wish.
double sc_time_stamp () { // Called by $time in Verilog
    return main_time; // converts to double, to match
    // what SystemC does
}

int get_rank_fromXY(int x, int y) {
    return 1 + ((x)+((PRONOC_T1)*y));
}

// MPI ID funcitons
int getDimX () {
    if (mpi_rank==0) // Should never happen
        return 0;
    else
        return (mpi_rank-1)%PRONOC_T1;
}

int getDimY () {
    if (mpi_rank==0) // Should never happen
        return 0;
    else
        return (mpi_rank-1)/PRONOC_T1;
}

int get_edge_rank (int port) {

	int m;
	for (m=0;m< MCS_NUM; m++){
		if(mc_map[m].x==tile_x && mc_map[m].y == tile_y && mc_map[m].p == port) return (m + 1 + (PRONOC_T1*PRONOC_T2));
	}
	return -1;
}


int getRankN () {
    if (tile_y == 0)
    	return get_edge_rank(PITON_PORT_N); 
       // return -1;
    else
        return get_rank_fromXY(tile_x, tile_y-1);
}

int getRankS () {
    if (tile_y+1 == PRONOC_T2)
       return get_edge_rank(PITON_PORT_S); 
       // return -1;
    else
        return get_rank_fromXY(tile_x, tile_y+1);
}

int getRankE () {
    if (tile_x+1 == PRONOC_T1)
        return get_edge_rank(PITON_PORT_E); 
       // return -1;
    else
        return get_rank_fromXY(tile_x+1, tile_y);
}

int getRankW () {
    if (mpi_rank==1) { // go to chipset
        return 0;
    }
    else if (tile_x == 0) {
       return get_edge_rank(PITON_PORT_W); 
       // return -1;
    }
    else {
        return get_rank_fromXY(tile_x-1, tile_y);
    }
}

void tick() {
    top->core_ref_clk =1;
    main_time += 250;
    top->eval();
#ifdef VERILATOR_VCD
    tfp->dump(main_time);
#endif
    top->core_ref_clk = 0;
    main_time += 250;
    top->eval();
#ifdef VERILATOR_VCD
    tfp->dump(main_time);
#endif
}



void mpi_work_opt() {
    int i;
    for (i=0;i<RANK_NUM;i++){
        if (MY_RANK[i] != -1)  mpi_send_chan(&top->noc_chanel_out[i], sizeof(top->noc_chanel_out[i]), MY_RANK[i], mpi_rank, ALL_NOC);
        if (MY_RANK[i] != -1)  mpi_receive_chan(&top->noc_chanel_in[i], sizeof(top->noc_chanel_in[i]), MY_RANK[i], ALL_NOC);
    }   
}



void mpi_tick() {
   
    top->core_ref_clk = 1;   
    top->eval();
    main_time += 250;
     
 #ifdef VERILATOR_VCD
    tfp->dump(main_time);
#endif
  
  
    for(int i=0; i<smart_max+2; i++) {  
        top->core_ref_clk = 0;
        mpi_work_opt();
        top->eval();
    }
    
     main_time += 250;
    
#ifdef VERILATOR_VCD
    tfp->dump(main_time);
#endif
   
    

}

void reset_and_init() {
// Clocks initial value
    top->core_ref_clk = 0;

// Resets are held low at start of boot
    top->sys_rst_n = 0;
    top->pll_rst_n = 0;
    top->ok_iob = 0;

// Mostly DC signals set at start of boot

    top->pll_bypass = 1; // trin: pll_bypass is a switch in the pll; not reliable
    top->clk_mux_sel = 0; // selecting ref clock
    top->pll_rangea = 1; // 10x ref clock
    top->async_mux = 0;
    tick();
    mpi_tick();

    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->pll_rst_n = 1;


    for (int i = 0; i < 10; i++) {
        tick();
    }
    top->clk_en = 1;


    for (int i = 0; i < 100; i++) {
        tick();
    }

    top->sys_rst_n = 1;


    for (int i = 0; i < 5000; i++) {
        tick();
    }

    top->ok_iob = 1;

}

vector<uint64_t> good_traps;
vector<uint64_t> bad_traps;




// Function to check traps per commit
int check_trap_per_commit(unsigned char inst_done, uint64_t phy_pc_w) {
    if (inst_done == 0) return CONTINUE;
    // Iterate over bad_traps
    for (const uint64_t &trap_value : bad_traps) {
        if (phy_pc_w == trap_value) {
           // printf("Bad trap detected at PC: %lx\n", phy_pc_w);
            return BAD_EXIT;
        }
    }
    // Iterate over good_traps
    for (const uint64_t &trap_value : good_traps) {
        if (phy_pc_w == trap_value) {
            //printf("Good trap detected at PC: %lx\n", phy_pc_w);
            return GOOD_EXIT;
        }
    }
    return CONTINUE;
}

// Function to check traps
int check_trap(void) {
    int trap = CONTINUE;
    int m = sizeof(top->inst_done);
    for (int i = 0; i < m; i++) {
        unsigned char inst_done = ((unsigned char*)(&top->inst_done))[i];
        uint64_t phy_pc_w = ((uint64_t*)(&top->phy_pc_w))[i];
        if (trap == CONTINUE) {
            trap = check_trap_per_commit(inst_done, phy_pc_w);
        }
    }
    return trap;
}


int main(int argc, char **argv, char **env) {
    //std::cout << "Started" << std::endl << std::flush;
    Verilated::commandArgs(argc, argv);
    top = new Vmetro_tile;
    //std::cout << "Vmetro_tile created" << std::endl << std::flush;    

    // MPI work 
    initialize();
    mpi_rank = getRank();
    mpi_size = getSize();    
    
    //std::cout << "Vmetro_tile MPI created" << std::endl << std::flush;
#ifdef KONATA_EN
    konata_signature_init();
    konata_signature->clear_output();
#endif

#ifdef VERILATOR_VCD
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace (tfp, 99);
    std::cout << "dunno why we entered" << std::endl << std::flush;
    std::string tracename ("my_metro_tile"+std::to_string(mpi_rank)+".vcd");
    const char *cstr = tracename.c_str();
    tfp->open(cstr);
    Verilated::debug(1);
#endif
    
    dest = (mpi_rank)? 0 : 1; 

    tile_x = getDimX();
    tile_y = getDimY();
    rankN  = getRankN();
    rankS  = getRankS();
    rankW  = getRankW();
    rankE  = getRankE();


    MY_RANK[NORTH] = rankN;
    MY_RANK[EAST]  = rankE;
    MY_RANK[WEST]  = rankW;
    MY_RANK[SOUTH] = rankS;

    #ifdef REPORT_RANKS
	printf("** RANK(%d): N:%d E:%d W:%d S:%d\n",mpi_rank, rankN, rankE, rankW, rankS);
    #endif
    
    //std::cout << "Vmetro_tile MPI middle" << std::endl << std::flush;

    #ifdef VERILATOR_VCD
    std::cout << "TILE size: " << mpi_size << ", rank: " << mpi_rank <<  std::endl;
    std::cout << "tile_y: " << tile_y << std::endl;
    std::cout << "tile_x: " << tile_x << std::endl;
    std::cout << "rankN: " << rankN << std::endl;
    std::cout << "rankS: " << rankS << std::endl;
    std::cout << "rankW: " << rankW << std::endl;
    std::cout << "rankE: " << rankE << std::endl;
    #endif

    top->default_chipid = 0;
    top->current_r_id = mpi_rank-1;
    
    int first_tile_id = (mpi_rank-1) * PRONOC_T3;
    for (int l=0; l<PRONOC_T3; l++ ){
        int current_tile_id = first_tile_id+l;
        top->default_coreid_x[l] =  current_tile_id % PITON_X_TILES;   //tile_x;
        top->default_coreid_y[l] =  current_tile_id / PITON_X_TILES;
        top->flat_tileid[l] = current_tile_id;        
        top->cpu_enable[l] = (current_tile_id < PITON_X_TILES * PITON_Y_TILES) ? 1 : 0;
    }
    //cpu_enable
    //std::cout << "Vmetro_tile MPI before reset" << std::endl << std::flush;

    reset_and_init();
    
    smart_max = top->smart_max;
    
    if (mpi_rank==1) std::cout << "smart_max=" << smart_max << std::endl << std::flush;
    
    good_traps =  get_traps (argc, argv,GOOD_TRAP);
    bad_traps =  get_traps (argc, argv,BAD_TRAP);

    //std::cout << "Vmetro_tile MPI after reset" << std::endl << std::flush;

    //bool test_exit = false;
    uint64_t checkTestEnd=TRAP_INITIAL_CHECK_DELAY;
    int local_trap=CONTINUE;
    int global_trap=CONTINUE;
    while (!Verilated::gotFinish() and global_trap==CONTINUE) {       
        mpi_tick();
        if(local_trap == CONTINUE ) local_trap = check_trap ();
        
        if (checkTestEnd==0) {            
            global_trap= mpi_check_trap (local_trap);
            checkTestEnd=TRAP_CHECK_INTERVAL;           
        }
        else {
            checkTestEnd--;
        }
    }
    
    checkTestEnd=TRAP_END_DELAY;
    while (!Verilated::gotFinish() and checkTestEnd!=0){  checkTestEnd--; mpi_tick();}
    
    
    unsigned int cache_st [CHACH_ST_SIZ];
    for(int i=0; i<CHACH_ST_SIZ; i++) cache_st[i] = top->cache_st[i];    

    #define MAX_PCK_SIZ 12
    uint64_t flit_st [6];
    uint64_t pck_st  [6][MAX_PCK_SIZ];
    for(int i=0; i<6; i++) {
        flit_st[i] = top->flit_st[i];
        for(int j=0; j<MAX_PCK_SIZ; j++) pck_st  [i][j] =top-> pck_st[i][j];
    }

    mpi_send_chan(&cache_st, sizeof(cache_st),  0, mpi_rank, PRINT_CACHE);
    mpi_send_chan(&flit_st,  sizeof(flit_st),   0, mpi_rank, PRINT_CACHE+1);
    mpi_send_chan(&pck_st ,  sizeof( pck_st),   0, mpi_rank, PRINT_CACHE+2);

    unsigned int hpm_st [HPM_ROW_WIDTH];
    for(int r=0; r<HPM_ROW_NUM; r++){
         // fill a row
         for(int i=0; i<HPM_ROW_WIDTH; i++){
                if(i+r*HPM_ROW_WIDTH<HPM_CNT_NUM)hpm_st[i] = top->hpm_st[i+r*HPM_ROW_WIDTH];
                else hpm_st[i] = 0;
         }
         //send a row
         mpi_send_chan(&hpm_st ,  sizeof(hpm_st),   0, mpi_rank, PRINT_CACHE+3);
    }
   
    

  //  std::cout << "ticks: " << std::setprecision(10) << sc_time_stamp() << " , cycles: " << sc_time_stamp()/500 << std::endl;

    #ifdef VERILATOR_VCD
    std::cout << "Trace done" << std::endl;
    tfp->close();
    #endif

    finalize();
    top->final();

    delete top;
    exit(0);
}
