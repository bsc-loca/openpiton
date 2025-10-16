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

#include "Vmetro_chipset.h"
#include "verilated.h"
#include <iostream>
//#define VERILATOR_VCD 0

#ifdef VERILATOR_VCD
#include "verilated_vcd_c.h"
#endif
#include <iomanip>


extern "C" void metro_mpi_init_jbus_model_call(const char* str, int oram);


#include "mcs_map_info.tmp.h"
#include "metro_mpi.h"

uint64_t main_time = 0; // Current simulation time
uint64_t clk = 0;
Vmetro_chipset* top;
int mpi_rank, dest, mpi_size;
short test_end=0;
short good_end=0;
short bad_end =0;
int smart_max=0;
MEM_STAT_t stat;



#ifdef PITON_LATMODEL
    #define NO_REQ  0
    #define RD_REQ  1
    #define WR_REQ  2
    uint64_t clk_cnt=0;   
    unsigned char  mem_valid_req [DELAY_MODEL_SYNC_CYCLES]={NO_REQ};   
    uint64_t mem_lat = 150;

    typedef struct {
        double sum;
        int count;  
        uint64_t min;
        uint64_t max;
        uint64_t mean;  
        uint64_t rd_cnt;  
        uint64_t wr_cnt;   
    } LATMODEL_t;

    LATMODEL_t lat_st;
    #define OP_FRQ_MHZ  1500
    extern "C" void delay_init_call(const char* curve_path, int freq);
    extern "C" unsigned long long  got_a_write_req_call(unsigned long long accessCycle);
    extern "C" unsigned long long  got_a_read_req_call(unsigned long long accessCycle);
    extern "C" double get_Bandwidth_call(void);

#endif


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



void  mpi_work_opt_chipset(){
    mpi_send_chan(&top->noc_chanel_out, sizeof(top->noc_chanel_out),  dest, mpi_rank, ALL_NOC);
    mpi_receive_chan(&top->noc_chanel_in, sizeof(top->noc_chanel_in), dest, ALL_NOC);
}





#ifdef PITON_LATMODEL
void  mpi_work_latmodel_chipset (){
    uint64_t index = clk_cnt % DELAY_MODEL_SYNC_CYCLES;  
    int mc_start_rank = PITON_X_TILES * PITON_Y_TILES +1; 
    if(index == DELAY_MODEL_SYNC_CYCLES-1 ){ 
        for (int i=0; i<MCS_NUM; i++){
            mpi_receive_chan(&mem_valid_req, sizeof(mem_valid_req), mc_start_rank+i, MEM_LAT);
            for(int k=0; k<DELAY_MODEL_SYNC_CYCLES;k++){
                if(mem_valid_req[k]==RD_REQ){
                    mem_lat = got_a_read_req_call (clk_cnt-DELAY_MODEL_SYNC_CYCLES+k);
                    lat_st.rd_cnt++;                
                }
                if(mem_valid_req[k]==WR_REQ){
                    mem_lat = got_a_write_req_call(clk_cnt-DELAY_MODEL_SYNC_CYCLES+k);
                    lat_st.wr_cnt++;
                }
 
#ifdef PITON_LATMODEL_FIX1
                mem_lat =1;
#endif 

#ifdef PITON_LATMODEL_FIX160
                mem_lat =160;
#endif               
                
               // if(mem_valid_req[k]==RD_REQ)  printf("RD=%lu; mem_lat =%lu\n", clk_cnt-DELAY_MODEL_SYNC_CYCLES+k,mem_lat );
               // if(mem_valid_req[k]==WR_REQ)  printf("WR=%lu;\n", clk_cnt-DELAY_MODEL_SYNC_CYCLES+k);
            }           
        }
        for (int i=0; i<MCS_NUM; i++){//send rd_latency to all memory controllers            
            mpi_send_chan   (&mem_lat, sizeof(mem_lat),   mc_start_rank+i, mpi_rank, MEM_LAT);
        }
        lat_st.count++;
        lat_st.sum+=mem_lat;
        if(mem_lat < lat_st.min) lat_st.min=mem_lat;
        if(mem_lat > lat_st.max) lat_st.max=mem_lat;
    }   
}
#endif


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
        mpi_work_latmodel_chipset();
    #endif

    for(int i=0; i<smart_max+2; i++) {
        top->core_ref_clk = 0;  
        mpi_work_opt_chipset();
        top->eval();
    }
    
    main_time += 250;
    
    #ifdef VERILATOR_VCD
    tfp->dump(main_time);
    #endif
}

void reset_and_init(std::string mem_image) {
    
//    fail_flag = 1'b0;
//    stub_done = 4'b0;
//    stub_pass = 4'b0;

//    // Clocks initial value
    top->core_ref_clk = 0;

//    // Resets are held low at start of boot
    top->sys_rst_n = 0;
    top->pll_rst_n = 0;

    top->ok_iob = 0;

//    // Mostly DC signals set at start of boot
//    clk_en = 1'b0;
    top->pll_bypass = 1; // trin: pll_bypass is a switch in the pll; not reliable
    top->clk_mux_sel = 0; // selecting ref clock
//    // rangeA = x10 ? 5'b1 : x5 ? 5'b11110 : x2 ? 5'b10100 : x1 ? 5'b10010 : x20 ? 5'b0 : 5'b1;
    top->pll_rangea = 1; // 10x ref clock
//    // pll_rangea = 5'b11110; // 5x ref clock
//    // pll_rangea = 5'b00000; // 20x ref clock
    
//    // JTAG simulation currently not supported here
//    jtag_modesel = 1'b1;
//    jtag_datain = 1'b0;

    top->async_mux = 0;

    test_end=0;
    good_end=0;
    bad_end=0;

    metro_mpi_init_jbus_model_call((char *) mem_image.c_str(), 0);
    
    //std::cout << "Before first ticks" << std::endl << std::flush;
    tick();
    mpi_tick();
    //std::cout << "After very first tick" << std::endl << std::flush;
//    // Reset PLL for 100 cycles
//    repeat(100)@(posedge core_ref_clk);
//    pll_rst_n = 1'b1;
    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->pll_rst_n = 1;

    //std::cout << "Before second ticks" << std::endl << std::flush;
//    // Wait for PLL lock
//    wait( pll_lock == 1'b1 );
    //while (!top->pll_lock) {
    //    tick();
    //}

    //std::cout << "Before third ticks" << std::endl << std::flush;
//    // After 10 cycles turn on chip-level clock enable
//    repeat(10)@(posedge `CHIP_INT_CLK);
//    clk_en = 1'b1;
    for (int i = 0; i < 10; i++) {
        tick();
    }
    top->clk_en = 1;

//    // After 100 cycles release reset
//    repeat(100)@(posedge `CHIP_INT_CLK);
//    sys_rst_n = 1'b1;
//    jtag_rst_l = 1'b1;
    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->sys_rst_n = 1;

//    // Wait for SRAM init, trin: 5000 cycles is about the lowest
//    repeat(5000)@(posedge `CHIP_INT_CLK);
    for (int i = 0; i < 5000; i++) {
        tick();
    }

//    top->diag_done = 1;

    //top->ciop_fake_iob.ok_iob = 1;
    top->ok_iob = 1;
    std::cout << "Reset complete (Chipset)" << std::endl << std::flush;
}

int main(int argc, char **argv, char **env) {
    //std::cout << "Started" << std::endl << std::flush;
    Verilated::commandArgs(argc, argv);
    
    //get mem.image path:
    std::string mem_image = get_mem_image_full_path(argc, argv);
    #ifdef PITON_LATMODEL
         std::string lat_model =  get_lat_model_full_path(argc, argv);
         delay_init_call((char *) lat_model.c_str(), OP_FRQ_MHZ);
         lat_st.sum=0;
         lat_st.count=0;  
         lat_st.min=0xFFFFFFFF;
         lat_st.max=0;
         lat_st.mean=0; 
         lat_st.rd_cnt=0;
         lat_st.wr_cnt=0;
         mem_lat = got_a_read_req_call (1);//initial delay
    #endif
    
    top = new Vmetro_chipset;
    //std::cout << "Vmetro_chipset created" << std::endl << std::flush;

#ifdef VERILATOR_VCD
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace (tfp, 99);
    tfp->open ("my_metro_chipset.vcd");

    Verilated::debug(1);
#endif

    // MPI work 
    initialize();
    mpi_rank = getRank();
    mpi_size = getSize();
    
    //std::cout << "CHIPSET size: " << mpi_size << ", mpi_rank: " << mpi_rank <<  std::endl;
    if (mpi_rank==0) {
        dest = 1;
    } else {
        dest = 0;
    }


    reset_and_init(mem_image);
    smart_max = top->smart_max;

    //bool test_exit = false;
    uint64_t checkTestEnd=TRAP_INITIAL_CHECK_DELAY;
    int local_trap=CONTINUE;
    int global_trap=CONTINUE;
    while (!Verilated::gotFinish() and global_trap==CONTINUE) { 
        mpi_tick();
        //Traps are detected only in tiles. The local trap for chispet is always in continue state
        if (checkTestEnd==0) {
            //std::cout << "Checking Finish CHIPSET" << std::endl;
            //mpi_send_finish(test_end, mpi_rank);
            global_trap= mpi_check_trap (local_trap);
            checkTestEnd=TRAP_CHECK_INTERVAL;
            //test_exit=test_end;
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
    stat.mc_num=-1;
    stat.dest =dest;

    int mc_start_rank = PITON_X_TILES * PITON_Y_TILES +1;


    #ifdef PITON_LATMODEL
    std::cout<<"---------Delay model Stats-------------"<< std::endl; 
    std::cout<<"Min, Mean, Max, Bandwidth, #rd ,#wr, Ratio, clk, RD_BW, WR_BW, RW_BW "  << std::endl;
    lat_st.mean=lat_st.sum/lat_st.count; 
    double bw = get_Bandwidth_call();
    double Ratio = (lat_st.rd_cnt*100) / (lat_st.wr_cnt + lat_st.rd_cnt);
    double RD_BW = (lat_st.rd_cnt*64)/(double)((clk_cnt*1000)/OP_FRQ_MHZ);
    double WR_BW = (lat_st.wr_cnt*64)/(double)((clk_cnt*1000)/OP_FRQ_MHZ);
    std::cout
        << lat_st.min  << ", " 
        << lat_st.mean << ", " 
        << lat_st.max  << ", " 
        << bw << ", " 
        << lat_st.rd_cnt << ", " 
        << lat_st.wr_cnt << ", " 
        << Ratio << ", " 
        << clk_cnt  << ", " 
        << RD_BW << ", " 
        << WR_BW << ", " 
        << RD_BW + WR_BW 
        << std::endl;
    std::cout<<"---------Delay model Stats-------------"<< std::endl;
    #endif

    std::cout<<"---------Memory Stats-------------"<< std::endl;
    std::cout<<"Mem num, MPI Rank, MPI Dest Rank, #flit_in, #flit_out, ticks, cycles "  << std::endl;
    print_static (stat,sc_time_stamp());
    for (int i=0; i<MCS_NUM; i++){
        mpi_receive_chan(&stat, sizeof(stat), mc_start_rank+i, PRINT_STAT);
        print_static (stat,sc_time_stamp());
    }
    std::cout<<"---------Memory Stats-------------"<< std::endl;
    
    std::cout<<"---------Cache Stats-------------"<< std::endl;
    std::cout<<"Tile num, l15_tag_indx, l15_dat_indx, l2_tag_indx, l2_dat_indx, l2_access, l2_miss, avg_lat"  << std::endl;
    unsigned int cache_st [CHACH_ST_SIZ];
    for (int i=1; i<mc_start_rank; i++){
        mpi_receive_chan(&cache_st, sizeof(cache_st), i, PRINT_CACHE);
        std::cout << i-1;
        for(int i=0; i<8; i+=2){
            float p = (((float) cache_st[i])  / (float)cache_st[i+1])*100;
            printf (", %.2f",p);
        }
        printf (", %u, %u",cache_st[8], cache_st[9]);
        printf (", %u",(cache_st[10] / cache_st[11]));
        std::cout << std::endl;
    }
    std::cout<<"---------Cache Stats-------------"<< std::endl;

    std::cout<<"---------Flit Stats-------------"<< std::endl;
    std::cout<<"Tile num, NoC1_out, NoC2_out, NoC3_out, NoC1_in, NoC2_in, NoC3_in"  << std::endl;
    uint64_t flit_st [6];
    for (int i=1; i<mc_start_rank; i++){
        mpi_receive_chan(&flit_st, sizeof(flit_st), i, PRINT_CACHE+1);
        std::cout << i-1;
        for(int j=0; j<6; j++){        	
            printf (", %lu",flit_st [j]);
        }
        std::cout << std::endl;
    }
    std::cout<<"---------Flit Stats-------------"<< std::endl;

    std::cout<<"---------Packet Stats-------------"<< std::endl;
    #define MAX_PCK_SIZ 12

    
            
    uint64_t pck_st  [6][MAX_PCK_SIZ];
    uint64_t pck_st_sum  [6][MAX_PCK_SIZ];
    char pck_st_print_en  [MAX_PCK_SIZ]={0};
    for(int j=0; j<6; j++){ for(int k=0;k<MAX_PCK_SIZ;k++){ pck_st_sum [j][k] = 0; pck_st_print_en[k]=0;}};

    const char* names [6] ={"NoC1_out", "NoC2_out", "NoC3_out", "NoC1_in" , "NoC2_in", "NoC3_in"};
    for (int i=1; i<mc_start_rank; i++){
        mpi_receive_chan(&pck_st, sizeof(pck_st), i, PRINT_CACHE+2);
        for(int j=0; j<6; j++){  
            //std::cout << i-1;  
            //printf (", %s", names[j]);   	
            for(int k=0;k<MAX_PCK_SIZ;k++){
                //printf (", %lu",pck_st [j][k]);
                pck_st_sum [j][k]+=pck_st [j][k];
                if(pck_st [j][k]>0) pck_st_print_en[k] =1;
            }
           // std::cout << std::endl;
        }
    }

    printf("NoC name"); 
    for(int k=0;k<MAX_PCK_SIZ;k++)  if(pck_st_print_en[k]) printf (",%uB",(k+1)*8);
    std::cout << std::endl;

    for(int j=0; j<6; j++){
            printf ("%s", names[j]);
            for(int k=0;k<MAX_PCK_SIZ;k++){
                if(pck_st_print_en[k]) printf (", %lu",pck_st_sum [j][k]);
            }
            std::cout << std::endl;
    }
    std::cout<<"---------Packet Stats-------------"<< std::endl;


    unsigned int hpm_st [HPM_ROW_WIDTH];
    extern const char * hpm_str[HPM_CNT_NUM];
    for(int r=0; r<HPM_ROW_NUM; r++){
        std::cout<<"---------HPM Stats "<< r << "-------------"<< std::endl;    
        std::cout<<"Tile num";

        for(int i=0; i<HPM_ROW_WIDTH; i++) if(i+r*HPM_ROW_WIDTH<HPM_CNT_NUM) printf (",%s", hpm_str[i+r*HPM_ROW_WIDTH]);   	
        std::cout << std::endl;

        for (int c=1; c<mc_start_rank; c++){
            mpi_receive_chan(&hpm_st, sizeof(hpm_st), c, PRINT_CACHE+3);
            std::cout << c-1;
            for(int i=0; i<HPM_ROW_WIDTH; i++){
                if(i+r*HPM_ROW_WIDTH<HPM_CNT_NUM) printf (", %u",hpm_st[i]);
            }
            std::cout << std::endl;
        }

        
        std::cout<<"---------HPM Stats "<< r << "-------------"<< std::endl;  
    }//hpm rows


    if (global_trap==GOOD_EXIT){
        std::cout << "Simulation -> PASS (HIT GOOD TRAP)"   << std::endl;
    }else if  (global_trap==BAD_EXIT){
        std::cout << "Simulation -> FAIL (HIT BAD TRAP)"    << std::endl;
    
    }else{//The program shouldnt come here at all
        std::cout << "Simulation -> UNKNOWN (HIT NO TRAP)"   << std::endl;
    }
    

    #ifdef VERILATOR_VCD
    std::cout << "Trace done" << std::endl;
    tfp->close();
    #endif

    finalize();

    delete top;
    exit(0);
}
