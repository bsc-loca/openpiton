// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 26.11.2018
// Description: Simple hello world program that prints the core id.
// Also runs correctly on manycore configs.
//

//#include <stdint.h>
#include <stdio.h>
#include "util.h"

#define INVAL_OP 0
#define FLUSH_OP 1
#define CLEAN_OP 2

// Core 0
#define ACCESS_CORE_0
#define STORE_CORE_0

// Core 1
#define ACCESS_CORE_1
//#define STORE_CORE_1

// CMO core access
#ifndef CMO_CORE
#define CMO_CORE 1
#endif

// CSR READ MACRO
#define __ASM_STR(x)	#x
#define csr_read(csr)                                           \
	({                                                      \
		register unsigned long __v;                     \
		__asm__ __volatile__("csrr %0, " __ASM_STR(csr) \
				     : "=r"(__v)                \
				     :                          \
				     : "memory");               \
		__v;                                            \
	})

int testid = 0;
int ret_code = 0;
volatile static uint32_t semaphore_val;
volatile int test_res;

int measure_read_time(int * data)
{
  int startTime, endTime;
  startTime = csr_read(cycle);
  test_res = *data;
  endTime = csr_read(cycle);

  return endTime - startTime; 
}

void setup_semaphore(int n_cores)
{
  semaphore_val = n_cores;
}

int semaphore_wait()
{
  ATOMIC_OP(semaphore_val, -1, add, w);
  while(semaphore_val != 0);
}

int cmo_access(int op, int * data)
{
  if(op == INVAL_OP)      __builtin_riscv_zicbom_cbo_inval(data);
  else if(op == FLUSH_OP) __builtin_riscv_zicbom_cbo_flush(data);
  else if(op == CLEAN_OP) __builtin_riscv_zicbom_cbo_clean(data);
  testid++;
  return measure_read_time(data);
} 


void assert_cmo(int time, int op)
{
  int failed_flag = 0;

  char * op_string;


  // Local modified data
  if(op == INVAL_OP)
  {
    op_string = "Inval";
    if(test_res != 0)
      failed_flag = 1;
  }
  else if(op == FLUSH_OP || op == CLEAN_OP)
  {
    op_string = (op == FLUSH_OP) ? "Flush" : "Clean";

    if(testid == 5)
      failed_flag = test_res != 1; // Local modify
    else if(testid == 6)
      failed_flag = test_res != 2; // Remote modify
    else
      failed_flag = test_res != 0; 
  }

  if(!failed_flag)
  {
    printf("Test %d passed using %s operation. Access after cmo took %d cycles\n", testid, op_string, time);
  }
  else{
    ret_code = -1;
    printf("Test %d has failed using %s operation\n", testid, op_string);
  }
}

// Core N-1 (last core) will be in charge of reading time
void test_cmos(int hartid, int n_cores)
{
  volatile static uint32_t * data = (int *) 0x80030000;
  int t_main = (n_cores -1); 
  int ** test_result;

  // One iteration per each ZICBOM operation (Flush, Inval, Clean)
  for(int i = 0; i < 3; i++)
  {
    // For stats/debug purposes
    if(hartid == t_main) testid = -1;

    barrier(n_cores);

    // TEST #0: CMO to non-cached data(I MESI)
    if(hartid == t_main){
      assert_cmo(cmo_access(i, data),i);
    }
    barrier(n_cores);

    // TEST #1: CMO to shared data (S MESI)
    *data;
    barrier(n_cores);
    if(hartid == t_main)
      assert_cmo(cmo_access(i, data),i);
    barrier(n_cores);

    // TEST #2: CMO to partially shared data (S MESI)
    if(hartid % 2 == 0)
      *data;
    barrier(n_cores);
    if(hartid == t_main)
      assert_cmo(cmo_access(i, data),i);
    barrier(n_cores);
    
    // TEST #3: CMO to local exclusive data (E MESI)
    if(hartid == t_main)
    {
      *data;
      assert_cmo(cmo_access(i, data),i);
    }
    barrier(n_cores);

    // TEST #4: CMO to remote (if n_cores > 1) exclusive data (E MESI)
    if(hartid == 0)
      *data;
    barrier(n_cores);
    if(hartid == t_main)
      assert_cmo(cmo_access(i, data),i);
    barrier(n_cores);

    // TEST #5: CMO to local modified data (M MESI)
    if(hartid == t_main)
    {
      *data = 1;
      assert_cmo(cmo_access(i, data),i);
    }
    barrier(n_cores);

    // TEST #6: CMO to remote (if n_cores > 1) modified data (M MESI)
    if(hartid == 0)
      *data = 2;
    barrier(n_cores);
    if(hartid == t_main)
      assert_cmo(cmo_access(i, data),i);
    barrier(n_cores);

    data++;
  }
}



int main(int argc, char** argv) {

  int hartid = argv[0][0];
  int num_cores = argv[0][1];
  
  for(int i = 1; i <= num_cores; i *= 2)
  {

    if(hartid == 0)
    {
      printf("CMO TEST WITH %d CORES\n\n", i);
      setup_semaphore(num_cores);
    }
    barrier(num_cores);
    if(hartid < i)
      test_cmos(hartid, i);
    
    semaphore_wait();
  }

  return ret_code;
}
