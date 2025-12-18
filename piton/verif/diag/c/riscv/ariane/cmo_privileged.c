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


//#define VERBOSE

#define USER_MODE 0
#define SUPERVISOR_MODE 1
#define VS_MODE 2
#define VU_MODE 3


// CMO ops
#define OP_INVAL 0
#define OP_FLUSH 1
#define OP_CLEAN 2
#define OP_ZERO  3

// Expected outputs
#define EXPECT_VALID         0
#define EXPECT_ILLEGAL_INSTR 1
#define EXPECT_INVAL         2
#define EXPECT_FLUSH         3
#define EXPECT_VIRTUAL_INSTR 4


// Flush possible states
#define FLUSH_DISABLE  0x00
#define FLUSH_ENABLE   0x40

// Zero possible states
#define ZERO_DISABLE   0x00
#define ZERO_ENABLE    0x80

// Inval possible states
#define INVAL_DISABLE  0x00
#define INVAL_DO_FLUSH 0x10
#define INVAL_ENABLE   0x30

void execute_test();
void switch_to_lower_privilege(uintptr_t user_main, int privilege_lvl);
int  trap_handler();
void pass();
void fail();



typedef struct{
  int menvcfg;
  int senvcfg;
  int henvcfg;
  int privilege_mode;
  int op;
  int expected_output;
  int illegal_flag;
} CPT_context; //CMO Privileged Test context struct

CPT_context test_array[1000];
int test_num = 0;
int test_id = 0;
volatile static uint32_t * data = (int *) 0x80300000;

int calc_expected_outcome(int op, int menvcfg, int senvcfg, int henvcfg, int priv_lvl)
{
  switch (op)
  {
  case OP_INVAL:

    // Priv_lvl will never be M_MODE
    if((menvcfg == INVAL_DISABLE) || ((priv_lvl == USER_MODE) && (senvcfg == INVAL_DISABLE)))
      return EXPECT_ILLEGAL_INSTR;

    if((priv_lvl == VS_MODE) && (henvcfg == INVAL_DISABLE) ||
       (priv_lvl == VU_MODE) && ((henvcfg == INVAL_DISABLE) || (senvcfg == INVAL_DISABLE)))
       return EXPECT_VIRTUAL_INSTR;

    if((menvcfg == INVAL_DO_FLUSH) ||
       ((priv_lvl == USER_MODE) && (senvcfg == INVAL_DO_FLUSH)) ||
       ((priv_lvl == VS_MODE)   && (henvcfg == INVAL_DO_FLUSH)) ||
       ((priv_lvl == VU_MODE)   && ((henvcfg == INVAL_DO_FLUSH) || senvcfg == INVAL_DO_FLUSH)))
       return EXPECT_FLUSH;
    
    return EXPECT_INVAL;

  case OP_CLEAN:
  case OP_FLUSH:
    
  // Priv_lvl will never be M_MODE
    if((menvcfg == FLUSH_DISABLE) || ((priv_lvl == USER_MODE) && (senvcfg == FLUSH_DISABLE)))
      return EXPECT_ILLEGAL_INSTR;

    if((priv_lvl == VS_MODE) && (henvcfg == FLUSH_DISABLE) ||
       (priv_lvl == VU_MODE) && ((henvcfg == FLUSH_DISABLE) || (senvcfg == FLUSH_DISABLE)))
       return EXPECT_VIRTUAL_INSTR;

    return EXPECT_VALID;
    
  case OP_ZERO:

    // Priv_lvl will never be M_MODE
    if((menvcfg == ZERO_DISABLE) || ((priv_lvl == USER_MODE) && (senvcfg == ZERO_DISABLE)))
      return EXPECT_ILLEGAL_INSTR;

    if((priv_lvl == VS_MODE) && (henvcfg == ZERO_DISABLE) ||
       (priv_lvl == VU_MODE) && ((henvcfg == ZERO_DISABLE) || (senvcfg == ZERO_DISABLE)))
       return EXPECT_VIRTUAL_INSTR;

    return EXPECT_VALID;
  }

}


void setup_test(CPT_context * test, int op, int menvcfg, int senvcfg, int henvcfg, int privilege_mode){
  test->menvcfg = menvcfg;
  test->senvcfg = senvcfg;
  test->henvcfg = henvcfg;
  test->op      = op;
  test->privilege_mode = privilege_mode;
  test->expected_output = calc_expected_outcome(op, menvcfg, senvcfg, henvcfg, privilege_mode);
  test->illegal_flag = 0;
}


static inline void test_wrapper(int test_id){

  if(test_id == test_num)
  {
    pass();
  }

  *data = 0;
  __builtin_riscv_zicbom_cbo_clean(data);

  csr_write(menvcfg, test_array[test_id].menvcfg);
  csr_write(senvcfg, test_array[test_id].senvcfg);
  csr_write(henvcfg, test_array[test_id].henvcfg);
  switch_to_lower_privilege((uintptr_t) &execute_test, test_array[test_id].privilege_mode);
};

void check_menvcfg_rw()
{
  int error = 0;
  int csr_val = (0xf << 4); // Sets CBIE[4:5], CBCFE[6] and CBZE[7] bits to 1

  // M-mode envcfg CSR
  csr_write(menvcfg, csr_val);
  int r_menvcfg = csr_read(menvcfg);
  if(r_menvcfg != csr_val)
  {
    error = 1;
    printf("Error: R/W failed to menvcfg CSR\n");
    printf("Read value: %x (Expected %x)\n", r_menvcfg, csr_val);
  }
  csr_write(menvcfg, 0);

  // S-mode envcfg CSR
  csr_write(senvcfg, csr_val);
  int r_senvcfg = csr_read(senvcfg);
  if(r_senvcfg != csr_val)
  {
    error = 1;
    printf("Error: R/W failed to senvcfg CSR\n");
    printf("Read value: %x (Expected %x)\n", r_senvcfg, csr_val);
  }
  csr_write(senvcfg, 0);

  // H-mode envcfg CSR
  csr_write(henvcfg, csr_val);
  int r_henvcfg = csr_read(henvcfg);
  if(r_henvcfg != csr_val)
  {
    error = 1;
    printf("Error: R/W failed to henvcfg CSR\n");
    printf("Read value: %x (Expected %x)\n", r_henvcfg, csr_val);
  }
  csr_write(henvcfg, 0);
  
  if(error)
    fail();
}

int main(int argc, char** argv) {

  while(argv[0][0] != 0); // This test will only check the main core



  csr_write(mtvec, &trap_handler);

  int cbie_cfg  [3] = {INVAL_DISABLE, INVAL_DO_FLUSH, INVAL_ENABLE};
  int cbcfe_cfg [2] = {FLUSH_DISABLE, FLUSH_ENABLE};
  int cbze_cfg  [2] = {ZERO_DISABLE,  ZERO_ENABLE};

  int cbie_size  = 3;
  int cbcfe_size = 2;
  int cbze_size  = 2;

 
  // Check that we can read and write to envcfg successfully
  check_menvcfg_rw();


  //setup_test -> test#, cmo operation, menvcfg, senvcfg, privilege_lvl, expected_outcome

  // Create function to calculate expected_outcome
  for(int priv_lvl = 0; priv_lvl < 4; priv_lvl++)
  {
    for(int i = 0; i < cbie_size ; i++)
    {
      for(int j = 0; j < cbcfe_size; j++)
      {
        for(int k = 0; k < cbze_size; k++)
        {
          int id = priv_lvl*(cbze_size * cbcfe_size * cbie_size) + i*(cbze_size * cbcfe_size) + j*cbze_size + k;
          id *= 4;
          setup_test(&test_array[id]  , OP_INVAL, cbie_cfg[i], cbcfe_cfg[j], cbze_cfg[k], priv_lvl);
          setup_test(&test_array[id+1], OP_FLUSH, cbie_cfg[i], cbcfe_cfg[j], cbze_cfg[k], priv_lvl);
          setup_test(&test_array[id+2], OP_CLEAN, cbie_cfg[i], cbcfe_cfg[j], cbze_cfg[k], priv_lvl);
          setup_test(&test_array[id+3], OP_ZERO , cbie_cfg[i], cbcfe_cfg[j], cbze_cfg[k], priv_lvl);
          test_num += 4;
        }
      }
    }
  }

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

  if(privilege_lvl == SUPERVISOR_MODE || privilege_lvl == VS_MODE)
  {
    asm volatile(
          "li t2, (1 << 11)\n" //set MPP=01
          "or t0, t0, t2\n"
          ::: "t0", "t2"
  );
  }
  asm volatile("csrw mstatus, t0\n");


  asm volatile(
          "lui   t1, 0x80000\n"
          "sll   t1, t1, 7\n"
          "csrrc t0, mstatus, t1"
          ::: "t0", "t1"
  );

  if(privilege_lvl == VS_MODE || privilege_lvl == VU_MODE)
  {
    asm volatile(
          "lui   t2, 0x80000\n" //set MPV=1
          "sll   t2, t2, 7\n"
          "csrrs t0, mstatus, t2"
          ::: "t1", "t2"
  );
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

  long int mepc;

  int cause = csr_read(mcause);
  switch(cause){
    // Illegal instruction
    case 2:
      test_array[test_id].illegal_flag = EXPECT_ILLEGAL_INSTR;
      mepc = csr_read(mepc);
      csr_write(mepc, mepc+4);
      restore_registers();
      asm volatile("mret");
      break;
    // U-mode ecall
    case 8:
      if(test_array[test_id].privilege_mode == USER_MODE || test_array[test_id].privilege_mode == VU_MODE)
      {
        #ifdef VERBOSE
        printf("Test %d passed. Priv lvl: %d \t OP: %d \t Menvcfg: %x \t Senvcfg: %x \t Henvcfg: %x \t Outcome: %d \n", test_id, test_array[test_id].privilege_mode, test_array[test_id].op,
                                                                                                                        test_array[test_id].menvcfg, test_array[test_id].senvcfg, test_array[test_id].henvcfg,
                                                                                                                        test_array[test_id].expected_output);
        #endif
        test_id++;
        test_wrapper(test_id);
      }
      else
      {
        printf("Test %d failed: User mode ecall not expected\n");
        fail();
      }
      break;
    // S-mode ecall
    case 9:
      if(test_array[test_id].privilege_mode != SUPERVISOR_MODE)
      {
        printf("Test %d failed: Supervisor mode ecall not expected\n");
        fail();
      }
      #ifdef VERBOSE
      printf("Test %d passed. Priv lvl: %d \t OP: %d \t Menvcfg: %x \t Senvcfg: %x \t Henvcfg: %x \t Outcome: %d \n", test_id, test_array[test_id].privilege_mode, test_array[test_id].op,
                                                                                                                      test_array[test_id].menvcfg, test_array[test_id].senvcfg, test_array[test_id].henvcfg,
                                                                                                                      test_array[test_id].expected_output);
      #endif VERBOSE
      test_id++;

      test_wrapper(test_id);

      break;

    // VS-mode ecall
    case 10:
      if(test_array[test_id].privilege_mode != VS_MODE)
      {
        printf("Test %d failed: V-Supervisor mode ecall not expected\n");
        fail();
      }
      #ifdef VERBOSE
      printf("Test %d passed. Priv lvl: %d \t OP: %d \t Menvcfg: %x \t Senvcfg: %x \t Henvcfg: %x \t Outcome: %d \n", test_id, test_array[test_id].privilege_mode, test_array[test_id].op,
                                                                                                                      test_array[test_id].menvcfg, test_array[test_id].senvcfg, test_array[test_id].henvcfg,
                                                                                                                      test_array[test_id].expected_output);
      #endif
      test_id++;

      test_wrapper(test_id);

      break;
    case 22:
      test_array[test_id].illegal_flag = EXPECT_VIRTUAL_INSTR;
      int val = csr_read(mtinst);
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
  
  volatile CPT_context test = test_array[test_id];


  switch (test.op)
  {
  case OP_INVAL:

    *data = 1;

    __builtin_riscv_zicbom_cbo_inval(data);
    if(test.illegal_flag != EXPECT_ILLEGAL_INSTR)
    {
      if(*data == 1 && test.expected_output == EXPECT_INVAL)
      {
        printf("Test %d failed: Expected inval operation instead of flush\n", test_id);
        printf("Menvcfg: %x\n", test.menvcfg);
        printf("Senvcfg: %x\n", test.senvcfg);
        fail();
      }
      else if(*data == 0 && test.expected_output == EXPECT_FLUSH)
      {
        printf("Test %d failed: Expected flush operation instead of inval\n", test_id);
        printf("Menvcfg: %x\n", test.menvcfg);
        printf("Senvcfg: %x\n", test.senvcfg);
        fail();
      }
    }
    
    break;

  case OP_FLUSH:
    __builtin_riscv_zicbom_cbo_flush(data);
    break;
  
  case OP_CLEAN:
    __builtin_riscv_zicbom_cbo_clean(data);
    break;

  case OP_ZERO:
    __builtin_riscv_zicboz_cbo_zero(data);
    break;
  }

  if((test.illegal_flag == EXPECT_ILLEGAL_INSTR && test.expected_output != EXPECT_ILLEGAL_INSTR) ||
       (test.illegal_flag != EXPECT_ILLEGAL_INSTR && test.expected_output == EXPECT_ILLEGAL_INSTR))
  {
      printf("Test %d failed: Illegal instruction outcome not expected %d, %d\n", test_id, test.illegal_flag, test.expected_output);
      printf("Priv lvl: %d \t OP: %d \t Menvcfg: %x \t Senvcfg: %x \t Henvcfg: %x \t Outcome: %d \n", test_array[test_id].privilege_mode, test_array[test_id].op,
                                                                                                                      test_array[test_id].menvcfg, test_array[test_id].senvcfg, test_array[test_id].henvcfg,
                                                                                                                      test_array[test_id].expected_output);
      fail();
  }
  if((test.illegal_flag == EXPECT_VIRTUAL_INSTR && test.expected_output != EXPECT_VIRTUAL_INSTR) ||
       (test.illegal_flag != EXPECT_VIRTUAL_INSTR && test.expected_output == EXPECT_VIRTUAL_INSTR))
  {
      printf("Test %d failed: Illegal instruction outcome not expected %d, %d\n", test_id, test.illegal_flag, test.expected_output);
      fail();
  }

  asm volatile("ecall");
}
