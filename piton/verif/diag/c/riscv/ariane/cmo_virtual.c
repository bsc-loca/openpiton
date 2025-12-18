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
#include "util.h"
#include <stdio.h>

// Core 0
#define ACCESS_CORE_0
#define STORE_CORE_0

// CMO core access
#ifndef CMO_CORE
#define CMO_CORE 0  
#endif


#define TEST_NUM 1

#define USER_MODE 0
#define SUPERVISOR_MODE 1

#define SV39_MODE 0x8UL

/* page table entry (PTE) fields */
#define PTE_V     0x001 /* Valid */
#define PTE_R     0x002 /* Read */
#define PTE_W     0x004 /* Write */
#define PTE_X     0x008 /* Execute */
#define PTE_U     0x010 /* User */
#define PTE_G     0x020 /* Global */
#define PTE_A     0x040 /* Accessed */
#define PTE_D     0x080 /* Dirty */

#define PGSHIFT 12
#define PTE_PPN_SHIFT 10

// CMO ops
#define OP_INVAL 0
#define OP_FLUSH 1
#define OP_ZERO  2

// Expected outputs
#define EXPECT_VALID         0
#define EXPECT_ILLEGAL_INSTR 1
#define EXPECT_INVAL         2
#define EXPECT_FLUSH         3

// Flush possible states
#define FLUSH_DISABLE  0x00
#define FLUSH_ENABLE   0x40

// Zero possible states
#define ZERO_DISABLE   0x00
#define ZERO_ENABLE    0x80

// Flush possible states
#define INVAL_DISABLE  0x00
#define INVAL_DO_FLUSH 0x50
#define INVAL_ENABLE   0x70


void execute_test();
void switch_to_lower_privilege(uintptr_t user_main, int privilege_lvl);
int  trap_handler();
void pass();
void fail();
int ra;

unsigned long pt[4][1UL << 9] __attribute__((aligned(1UL << 12)));


typedef struct{
  int menvcfg;
  int senvcfg;
  int privilege_mode;
  int op;
  int expected_output;
  int illegal_flag;
} CPT_context; //CMO Privileged Test context struct

CPT_context test_array[TEST_NUM];
int test_id = 0;


void setup_test(CPT_context * test, int op, int menvcfg, int senvcfg, int privilege_mode, int expected_output){
  test->menvcfg = menvcfg;
  test->senvcfg = senvcfg;
  test->op      = op;
  test->privilege_mode = privilege_mode;
  test->expected_output = expected_output;
  test->illegal_flag = 0;
}


static inline void test_wrapper(int test_id){

  if(test_id == TEST_NUM)
  {
    pass();
  }

  //csr_write(menvcfg, test_array[test_id].menvcfg);
  //csr_write(senvcfg, test_array[test_id].senvcfg);
  switch_to_lower_privilege((uintptr_t) &execute_test, test_array[test_id].privilege_mode);
};

void virtual_mem_setup(){


  int satp_val = (uintptr_t) pt[0] >> PGSHIFT;
  
  // In SV39 virtual addresses can be broken into PAGE_ID (PGID), first 27 bits, and PAGE_OFFSET (PGOFF), last 12 bits

                                                                    //       PGID  PGOFF
  pt[0][2] = (uintptr_t) pt[1] >> PGSHIFT << PTE_PPN_SHIFT | PTE_V; // From 0x80000 000 to 0xbffff fff

  pt[1][0] = (uintptr_t) pt[2] >> PGSHIFT << PTE_PPN_SHIFT | PTE_V; // From 0x80000 000 to 0x801ff fff
  //pt[2][0] = (uintptr_t) pt[3] >> PGSHIFT << PTE_PPN_SHIFT | PTE_V;

  pt[2][0] = (0x80000) << PTE_PPN_SHIFT  | PTE_X | PTE_V | PTE_A | PTE_U;                         //0x80000 000 to 0x80000 fff -> Instruction page region 
  pt[2][1] = (0x80001) << PTE_PPN_SHIFT  | PTE_X | PTE_V | PTE_A | PTE_U;                         //0x80001 000 to 0x80001 fff -> Instruction page region
  pt[2][2] = (0x80002) << PTE_PPN_SHIFT  | PTE_R | PTE_V | PTE_A | PTE_U;                         //0x80002 000 to 0x80002 fff -> Read/Accessed page region
  pt[2][3] = (0x80003) << PTE_PPN_SHIFT  | PTE_R | PTE_W | PTE_V | PTE_A | PTE_U | PTE_D; //0x80003 000 to 0x80003 fff -> R/W Accessed/Dirty page region

  

  asm volatile(
        
        // Set mepc to the user program entry point
        "li  t0, 0x1\n"
        "slli t0, t0, 63\n"
        "mv  t1, %0\n"
        "or t0, t0, t1\n"
        "csrw satp, t0\n"
        :
        : "r"(satp_val)
        : "t0", "t1"
        
    );
  // SV39, no ASID def
  //csr_write(satp, (SV39_MODE << 59 | ((uintptr_t) pt[0] >> 12)));
}

int main(int argc, char** argv) {

  while(argv[0][0] != 0); // This test will only check the main core


  csr_write(menvcfg, FLUSH_ENABLE | ZERO_ENABLE | INVAL_ENABLE);
  csr_write(senvcfg, FLUSH_ENABLE | ZERO_ENABLE | INVAL_ENABLE);
  csr_write(mtvec, &trap_handler);

  virtual_mem_setup();
 

  // Execute test
  test_wrapper(test_id);

  return 0;
}

void inline set_lower_MPP(int privilege_lvl)
{
  asm volatile(
          // Set the MPP field (bits 12–11) of mstatus to 00 for user mode
          "csrr  t0, mstatus\n"
          "li    t1, ~(3 << 11)\n"   // clear MPP bits
          "and   t0, t0, t1\n"
          ::: "t0", "t1"
        );
  

  if(privilege_lvl == SUPERVISOR_MODE)
  {
    asm volatile(
          "li t2, (1 << 11)\n" //set MPP=01
          "or t0, t0, t2\n"
          ::: "t0", "t2"
  );
  asm volatile("csrw mstatus, t0\n");

  }
  

}

// Function to switch from M-mode to U-mode
void switch_to_lower_privilege(uintptr_t user_main, int privilege_lvl) {
    uintptr_t user_stack = 0x80100000;
    uintptr_t user_pc = user_main;

    set_lower_MPP(privilege_lvl); 

    asm volatile(
        
        // Set mepc to the user program entry point
        "csrw  mepc, %0\n"

        "csrw mscratch, sp\n"

        // Set the user stack pointer
        "mv    sp, %1\n"

        // Return to lower privilege (U-mode) using mret
        "mret\n"
        :
        : "r"(user_pc), "r"(user_stack)
        : "t0", "t1"
    );
}


int trap_handler()
{
  // Save user mode regs
  save_registers();

  int cause = csr_read(mcause);
  long int mepc;
  switch(cause){
    case 2: 
      test_array[test_id].illegal_flag = EXPECT_ILLEGAL_INSTR;
      mepc = csr_read(mepc);
      csr_write(mepc, mepc+4);
      restore_registers();
      asm volatile("mret");
      break;
    case 8:
      if(test_array[test_id].privilege_mode != USER_MODE)
      {
        printf("Test %d failed: User mode ecall not expected\n");
        fail();
      }

      printf("Test %d passed\n", test_id);
      test_id++;
      test_wrapper(test_id);

      break;
    case 9:
      if(test_array[test_id].privilege_mode != SUPERVISOR_MODE)
      {
        printf("Test %d failed: Supervisor mode ecall not expected\n");
        fail();
      }
      printf("Test %d passed\n", test_id);
      test_id++;
      
      test_wrapper(test_id);

      break;
    case 15:
      printf("Store trap fault\n");
      mepc = csr_read(mepc);
      csr_write(mepc, mepc+4);
      restore_registers();
      asm volatile("mret");
      break;
    default:
      printf("Fail: mstatus %d\n", cause);
      fail();
      break;  
  }
}
        

void execute_test()
{

  __builtin_riscv_zicbom_cbo_clean((void *)0x80002000);  
  __builtin_riscv_zicbom_cbo_clean((void *)0xfff00000); // Store page fault

  __builtin_riscv_zicbom_cbo_inval((void *)0x80002010); 
  __builtin_riscv_zicbom_cbo_inval((void *)0xfff00010); // Store page fault

  __builtin_riscv_zicbom_cbo_flush((void *)0x80002020);
  __builtin_riscv_zicbom_cbo_flush((void *)0xfff00020); // Store page fault

  __builtin_riscv_zicboz_cbo_zero((void *) 0x80003000);
  __builtin_riscv_zicboz_cbo_zero((void *) 0xfff00030); // Store page fault

  void * data = (void *) 0xfff00050;
  asm volatile("prefetch.r 0(%0)" :: "r"(data)); // Prefetches should not issue a store fault



  asm volatile("ecall");
}
