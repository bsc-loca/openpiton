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


#define STORE_CORE_0
//#define STORE_CORE_1
#define ACCESS_CORE_0
#define ACCESS_CORE_1
#ifndef CMO_CORE
#define CMO_CORE 1  
#define CACHELINE 64 
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


// static void __attribute__((noinline)) barrier(int ncores)
// {
//   static volatile int sense;
//   static volatile int count;
//   static __thread int threadsense;

//   __sync_synchronize();

//   threadsense = !threadsense;
//   if (__sync_fetch_and_add(&count, 1) == ncores-1)
//   {
//     count = 0;
//     sense = threadsense;
//   }
//   else while(sense != threadsense)
//     ;

//   __sync_synchronize();
// }
int temp = 0;
int sum = 0; 

#pragma GCC optimize ("O0")
int doNothing()
{
  return temp++;
}

int main(int argc, char** argv) {

  // synchronization variable
  volatile static uint32_t amo_cnt = 0;
  volatile void * data = (void *) &doNothing;
  long startTime, endTime = 0;
  uint32_t time_no_inval;
  uint32_t time_inval; 
  int iterations = CACHELINE / sizeof(*data);
  temp++;
  sum += doNothing();
  
  // synchronize with other cores and wait until it is this core's turn
  while(argv[0][0] != amo_cnt);

  #ifdef ACCESS_CORE_0
  if(argv[0][0] == 0)
  {
    sum += doNothing();
  }
  #endif


  #ifdef ACCESS_CORE_1
  if(argv[0][0] == 1)
  {
    startTime = csr_read(cycle);
    sum += doNothing(); 
    endTime = csr_read(cycle);
    time_no_inval = endTime - startTime;
  }
  #endif


  if(argv[0][0] == CMO_CORE) //Only core 1
  {

  //__builtin_riscv_zicbom_cbo_inval(data);
  //__builtin_riscv_zicbom_cbo_clean(data);
  __builtin_riscv_zicbom_cbo_flush(data);
  //__builtin_riscv_zicboz_cbo_zero(data);
  startTime = csr_read(cycle);
  sum += doNothing();
  endTime = csr_read(cycle);
  time_inval = endTime - startTime;
  
  printf("%d \t time inval: %d \t time not inval:%d\n", sum, time_inval, time_no_inval);

  }

  ATOMIC_OP(amo_cnt, 1, add, w);

  return 0;
}
