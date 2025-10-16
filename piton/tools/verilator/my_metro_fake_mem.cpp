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

#include "Vmetro_fake_mem.h"
#include "verilated.h"
#include <iostream>
//#define VERILATOR_VCD 0

#ifdef VERILATOR_VCD
#include "verilated_vcd_c.h"
#endif
#include <iomanip>

#include "mcs_map_info.tmp.h"
#include "metro_mpi.h"

extern "C" void metro_mpi_init_jbus_model_call(const char *str, int oram);


uint64_t main_time = 0; // Current simulation time
uint64_t clk = 0;
Vmetro_fake_mem* top;
int mpi_rank, dest, mpi_size;
short test_end=0;
int smart_max=0;

#ifdef PITON_LATMODEL
    #define NO_REQ  0
    #define RD_REQ  1
    #define WR_REQ  2
    uint64_t clk_cnt=0;   
    unsigned char  mem_valid_req [DELAY_MODEL_SYNC_CYCLES]={NO_REQ};   
    uint64_t mem_lat = 150;
#endif

MEM_STAT_t stat;





#ifdef VERILATOR_VCD
VerilatedVcdC* tfp;
#endif
// This is a 64-bit integer to reduce wrap over issues and
// // allow modulus. You can also use a double, if you wish.
double sc_time_stamp () { // Called by $time in Verilog
return main_time; // converts to double, to match
// what SystemC does
}

void tick() {
    top->core_ref_clk = 1;
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



void  mpi_work_opt_fake_mem(){
    //test_end = test_end or (top->good_end==1 or top->bad_end==1);
    
    mpi_send_chan(&top->noc_chanel_out, sizeof(top->noc_chanel_out),  dest, mpi_rank, ALL_NOC);
    mpi_receive_chan(&top->noc_chanel_in, sizeof(top->noc_chanel_in), dest, ALL_NOC);
}
#ifdef PITON_LATMODEL

void  mpi_work_on_latmodel (){
    uint64_t index = clk_cnt % DELAY_MODEL_SYNC_CYCLES;
        
    mem_valid_req[index] = 
        (top->got_rd & 0x1== 0x1) ? RD_REQ :
        (top->got_wr & 0x1== 0x1) ? WR_REQ :
        NO_REQ;
    if(index == DELAY_MODEL_SYNC_CYCLES-1 ){//send rd/wr info in each DELAY_MODEL_SYNC_CYCLES cycle 
        mpi_send_chan   (&mem_valid_req, sizeof(mem_valid_req),  0, mpi_rank, MEM_LAT);
        mpi_receive_chan(&mem_lat, sizeof(mem_lat), 0, MEM_LAT);
        top->rd_lat_in = mem_lat;
        //printf("mem_lat=%lu\n;",mem_lat);
    }    
}
#endif

int get_rank_fromXY(int x, int y) {
    return 1 + ((x)+((PRONOC_T1)*y));
}


void mpi_tick() {
    top->core_ref_clk = 1;    

    #ifdef PITON_LATMODEL
        if(top->sys_rst_n == 1) clk_cnt++;
    #endif  
    top->eval();
    main_time += 250;
    
    #ifdef VERILATOR_VCD
    tfp->dump(main_time);
    #endif
    
    #ifdef PITON_LATMODEL
       mpi_work_on_latmodel();
    #endif
    
    for(int i=0; i<smart_max+2; i++) {
        top->core_ref_clk = 0;  
        mpi_work_opt_fake_mem();
        top->eval();
    }
    
    main_time += 250;
    
    #ifdef VERILATOR_VCD
    tfp->dump(main_time);
    #endif 
}

void reset_and_init(std::string mem_image) {
    

    top->core_ref_clk = 0;

    metro_mpi_init_jbus_model_call((char *) mem_image.c_str(), 0);

    //std::cout << "Before first ticks" << std::endl << std::flush;
    tick();
    mpi_tick();
  
    for (int i = 0; i < 100; i++) {
        tick();
    }
   // top->pll_rst_n = 1;

   
    for (int i = 0; i < 10; i++) {
        tick();
    }
   // top->clk_en = 1;

//    // After 100 cycles release reset

    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->sys_rst_n = 1;

//    // Wait for SRAM init, trin: 5000 cycles is about the lowest
//    repeat(5000)@(posedge `CHIP_INT_CLK);
    for (int i = 0; i < 5000; i++) {
        tick();
    }


    std::cout << "Reset complete (fake_mem)" << std::endl << std::flush;
}

int main(int argc, char **argv, char **env) {
    //std::cout << "Started" << std::endl << std::flush;
    Verilated::commandArgs(argc, argv);
     //get mem.image path:
    std::string mem_image = get_mem_image_full_path(argc, argv);
    top = new Vmetro_fake_mem;
    //std::cout << "Vmetro_fake_mem created" << std::endl << std::flush;

#ifdef VERILATOR_VCD
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace (tfp, 99);
    tfp->open ("my_metro_fake_mem.vcd");

    Verilated::debug(1);
#endif

    // MPI work 
    initialize();
    mpi_rank = getRank();
    mpi_size = getSize();
    
    //printf("*************rank=%d\n",rank);
    
    //MC RANK starts with 1+ piton_x*piton_y
    int mc_start_rank = PRONOC_T1 * PRONOC_T2 +1;
    int mc_num = mpi_rank - mc_start_rank;
    if(mc_num >= MCS_NUM && MCS_NUM> 0){
    	printf("Error: invalid rank (%d) for fake mem. It mapped to mc (%d) while the number of MC are %d\n",mpi_rank,mc_num,MCS_NUM);
    	exit(1);
    }
    //printf("*************mc_num=%d\n",mc_num);
    dest =get_rank_fromXY(mc_map[mc_num].x , mc_map[mc_num].y);
    // printf("*************dest=%d\n",dest);
    //std::cout << "fake_mem size: " << mpi_size << ", mpi_rank: " << mpi_rank <<  std::endl;
    


    reset_and_init(mem_image);
    smart_max = top->smart_max;

    top->default_chipid = 0;
    top->default_coreid_x =  mc_map[mc_num].x;   //tile_x;
    top->default_coreid_y =  mc_map[mc_num].y;
    top->flat_tileid =  mc_map[mc_num].id;              
    #ifdef PITON_LATMODEL
    top->rd_lat_in = mem_lat;
    #endif
   
    //bool test_exit = false;
    uint64_t checkTestEnd=TRAP_INITIAL_CHECK_DELAY;
    int local_trap=CONTINUE;
    int global_trap=CONTINUE;
    while (!Verilated::gotFinish() and global_trap==CONTINUE) { 
        mpi_tick();
        //Traps are detected only in tiles. The local trap for fake memory is always in continue state
        if (checkTestEnd==0) {
            //std::cout << "Checking Finish fake_mem" << std::endl;
            //test_exit= mpi_receive_finish();
            checkTestEnd=TRAP_CHECK_INTERVAL;
            global_trap= mpi_check_trap (local_trap);
            //std::cout << "Finishing: " << test_end << std::endl;
        }
        else {
            checkTestEnd--;
        }
    }
    
    checkTestEnd=TRAP_END_DELAY;
    while (!Verilated::gotFinish() and checkTestEnd!=0){  checkTestEnd--; mpi_tick();}

     stat.flit_in_num =top->flit_i_cnts;
     stat.flit_out_num =top->flit_o_cnts;
     stat.rank=mpi_rank;
     stat.mc_num=mc_num;
     stat.dest =dest;

     mpi_send_chan(&stat, sizeof(stat),  0, mpi_rank, PRINT_STAT);


  

    #ifdef VERILATOR_VCD
    std::cout << "Trace done" << std::endl;
    tfp->close();
    #endif

    finalize();

    delete top;
    exit(0);
}
