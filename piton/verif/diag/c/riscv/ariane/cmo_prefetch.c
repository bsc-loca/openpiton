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

#define CACHE_LINE 64 // Cache line size is 64B


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


int measure_prefetch()
{
  int sum, initial_time, final_time;
  int n = 2048;
  int scalar = 7.21;
  double x[n];
  int block = CACHE_LINE / sizeof(double);

  // Initialize x vector
  for(int i = 0; i < n; i++)
  {
    x[i] = i;
  }

  initial_time = csr_read(cycle);

  for(int i=0; i < n; i+=block)
  {
    __builtin_prefetch((void *) &x[i+block], 0); // Software prefetch to next block

    for(int j=0; j < block; j++){
      sum += x[i+j] / scalar;
    }
  }

  final_time = csr_read(cycle);

  asm volatile(""::"r"(sum):"memory"); //Do not optimize function

  return final_time - initial_time;
}

int measure_baseline()
{
  int sum, initial_time, final_time;
  int n = 2048;
  int scalar = 7.21;
  double x[n];
  int block = CACHE_LINE / sizeof(double);

  // Initialize x vector
  for(int i = 0; i < n; i++)
  {
    x[i] = i;
  }

  initial_time = csr_read(cycle);

  for(int i=0; i < n; i+=block)
  {
    for(int j=0; j < block; j++){
      sum += x[i+j] / scalar;
    }
  }

  final_time = csr_read(cycle);

  asm volatile(""::"r"(sum):"memory"); //Do not optimize function

  return final_time - initial_time;
}


int main(int argc, char** argv) {

  // synchronization variable
  volatile static uint32_t amo_cnt = 0;
  volatile static uint32_t * data = (int *) 0x80030000;
  long startTime, endTime = 0;
  uint32_t time_no_inval;
  uint32_t time_inval; 
  
  // synchronize with other cores and wait until it is this core's turn
  while(argv[0][0] != amo_cnt);

  asm volatile("prefetch.i 1024(%0)" :: "r"(data));

  //asm volatile("prefetch.r 1024(%0)" :: "r"(data));

  __builtin_prefetch((void *) data, 0);    //prefetchr instruction
  __builtin_prefetch((void *) data, 1);    //prefetchw instruction
  // CMO_INVAL(&data);
  // increment atomic counter

  //*data;
  int baseline_time = measure_baseline();
  printf("Finished measuring baseline\n");
  int prefetch_time = measure_prefetch();


  printf("Baseline time: %d \t Prefetch_time: %d \n", baseline_time, prefetch_time);

  ATOMIC_OP(amo_cnt, 1, add, w);

  return 0;
}
