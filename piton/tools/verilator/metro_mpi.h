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

#ifndef METRO_MPI_H
#define METRO_MPI_H

#include <cstdint>    
#include <iostream>
#include <mpi.h>
#include <vector>

using namespace std;

#define DELAY_MODEL_SYNC_CYCLES  128 
#define CHACH_ST_SIZ             12

#define CONTINUE 0  // No exit condition
#define GOOD_EXIT 1 // Good exit condition
#define BAD_EXIT 2  // Bad exit condition

#ifndef TRAP_INITIAL_CHECK_DELAY
#define TRAP_INITIAL_CHECK_DELAY  14000  // Initial delay before first trap check
#endif

#ifndef TRAP_CHECK_INTERVAL
#define TRAP_CHECK_INTERVAL       2000   // Delay between consecutive trap checks
#endif

#ifndef TRAP_END_DELAY
#define TRAP_END_DELAY            14000  // Delay to end simulation after trap is detected
#endif

//#define PITON_LATMODEL_FIX1
//#define PITON_LATMODEL_FIX160
const int ALL_NOC      = 1;
const int PRINT_STAT   = 2;
const int PRINT_CACHE  = 3;
const int MEM_LAT      = 4;
// Compilation flags parameters
const int PITON_X_TILES = X_TILES;
const int PITON_Y_TILES = Y_TILES;

typedef struct MEM_STAT {
  uint64_t flit_in_num;
  uint64_t flit_out_num;
  int      rank;
  int      mc_num;
  int      dest;
} MEM_STAT_t;

void initialize();
int getRank();
int getSize();
void finalize();
unsigned short mpi_receive_finish();
void mpi_send_finish(unsigned short message, int rank);
void mpi_send_chan(void * chan, size_t len, int dest, int rank, int flag);
void mpi_receive_chan(void * chan, size_t len, int origin, int flag);
void print_static (MEM_STAT_t stat, uint64_t ticks);
int mpi_check_trap (int);
string get_mem_image_full_path (int, char **);
string get_lat_model_full_path (int, char **);
const bool  GOOD_TRAP=0;
const bool  BAD_TRAP=1;
vector<uint64_t>  get_traps (int , char **,bool);

enum {
  //HPM EVENTS
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
  HPM_CNT_NUM=47
};

const int HPM_ROW_WIDTH=10; // maximum hpm value sent at once
const int HPM_ROW_NUM=(HPM_CNT_NUM % HPM_ROW_WIDTH)? (HPM_CNT_NUM/HPM_ROW_WIDTH)+1 : (HPM_CNT_NUM/HPM_ROW_WIDTH);   // maximum hpm lines

#define HPM_STRING \
const char * hpm_str[HPM_CNT_NUM] = { \
"branch_miss",\
"is_branch",\
"branch_taken",\
"exe_st",\
"exe_ld",\
"icache_req",\
"icache_kill",\
"stall_if",\
"stall_id",\
"stall_rr",\
"stall_exe",\
"stall_wb",\
"icache_miss_l2_hit",\
"icache_miss_kill",\
"icache_busy",\
"icache_miss_time",\
"ld_st",\
"data_depend",\
"struct_depend",\
"grad_list_full",\
"free_list_empty",\
"itlb_acc",\
"itlb_miss",\
"dtlb_acc",\
"dtlb_miss",\
"ptw_buf_hit",\
"ptw_buf_miss",\
"itlb_stall",\
"dcache_stall",\
"dcache_stall_refill",\
"dcache_rtab_rollback",\
"dcache_req_onhold",\
"dcache_prefetch_req",\
"dcache_rd_req",\
"dcache_wr_req",\
"dcache_cmo_req",\
"dcache_uncached_req",\
"dcache_miss_rd_req",\
"dcache_miss_wr_req",\
"stall_ir",\
"l2_miss",\
"l2_acc",\
"l15_miss",\
"l15_acc",\
"roi_cycles",\
"dcache_wbf_wr",\
"dcache_wbf_rdy",\
};


#endif
