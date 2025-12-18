// Copyright (c) 2012-2015, The Regents of the University of California (Regents).
// All Rights Reserved.

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the Regents nor the
//    names of its contributors may be used to endorse or promote products
//    derived from this software without specific prior written permission.

// IN NO EVENT SHALL REGENTS BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT,
// SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING
// OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF REGENTS HAS
// BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// REGENTS SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE. THE SOFTWARE AND ACCOMPANYING DOCUMENTATION, IF ANY, PROVIDED
// HEREUNDER IS PROVIDED "AS IS". REGENTS HAS NO OBLIGATION TO PROVIDE
// MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

// this file has been copied and adapted for the OpenPiton testbench

#ifndef __UTIL_H
#define __UTIL_H


// some OpenPiton-specific defines
#define PITON_UART_ADDRESS  0xFFF0C2C000ULL
// this is used in piton stream to terminate correctly
#define PITON_TEST_GOOD_END 0x8100000000ULL
#define PITON_TEST_BAD_END  0x8200000000ULL


extern void setStats(int enable);

#include <stdint.h>

// instantiation macros for atomic memory operation (non LR/SC)
// see also
// https://github.com/torvalds/linux/blob/ef78e5ec9214376c5cb989f5da70b02d0c117b66/arch/riscv/include/asm/atomic.h#L94
#define ATOMIC_FETCH_OP(ret, mem, i, asm_op, asm_type) \
  __asm__ __volatile__ (                               \
    " amo" #asm_op "." #asm_type " %1, %2, %0"         \
    : "+A" (mem), "=r" (ret)                           \
    : "r" (i)                                          \
    : "memory");

#define ATOMIC_OP(mem, i, asm_op, asm_type)      \
  __asm__ __volatile__ (                         \
    " amo" #asm_op "." #asm_type " zero, %1, %0" \
    : "+A" (mem)                                 \
    : "r" (i)                                    \
    : "memory");

#define LR_OP(ret, mem, asm_type)               \
  __asm__ __volatile__ (                        \
    " lr." #asm_type " %1, %0"                  \
    : "+A" (mem), "=r" (ret)                    \
    :                                           \
    : "memory");

#define SC_OP(ret, mem, i, asm_type)            \
  __asm__ __volatile__ (                        \
    " sc." #asm_type " %1, %2, %0"              \
    : "+A" (mem), "=r" (ret)                    \
    : "r" (i)                                   \
    : "memory");


// CSR READ/WRITE MACROS
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

#define csr_write(csr, val)					\
({								\
	unsigned long __v = (unsigned long)(val);		\
	__asm__ __volatile__ ("csrw " __ASM_STR(csr) ", %0"	\
			      : : "rK" (__v)			\
			      : "memory");			\
})


#define static_assert(cond) switch(0) { case 0: case !!(long)(cond): ; }

static int verify(int n, const volatile int* test, const int* verify)
{
  int i;
  // Unrolled for faster verification
  for (i = 0; i < n/2*2; i+=2)
  {
    int t0 = test[i], t1 = test[i+1];
    int v0 = verify[i], v1 = verify[i+1];
    if (t0 != v0) return i+1;
    if (t1 != v1) return i+2;
  }
  if (n % 2 != 0 && test[n-1] != verify[n-1])
    return n;
  return 0;
}

static int verifyDouble(int n, const volatile double* test, const double* verify)
{
  int i;
  // Unrolled for faster verification
  for (i = 0; i < n/2*2; i+=2)
  {
    double t0 = test[i], t1 = test[i+1];
    double v0 = verify[i], v1 = verify[i+1];
    int eq1 = t0 == v0, eq2 = t1 == v1;
    if (!(eq1 & eq2)) return i+1+eq1;
  }
  if (n % 2 != 0 && test[n-1] != verify[n-1])
    return n;
  return 0;
}

static void __attribute__((noinline)) barrier(int ncores)
{
  static volatile int sense;
  static volatile int count;
  static __thread int threadsense;

  __sync_synchronize();

  threadsense = !threadsense;
  if (__sync_fetch_and_add(&count, 1) == ncores-1)
  {
    count = 0;
    sense = threadsense;
  }
  else while(sense != threadsense)
    ;

  __sync_synchronize();
}

static inline void save_registers() {
    asm volatile (
        "csrrw sp, mscratch, sp\n\t"

        "sd x1, 0(sp)\n\t"
        "sd x3, 16(sp)\n\t"
        "sd x4, 24(sp)\n\t"
        "sd x5, 32(sp)\n\t"
        "sd x6, 40(sp)\n\t"
        "sd x7, 48(sp)\n\t"
        "sd x8, 56(sp)\n\t"
        "sd x9, 64(sp)\n\t"
        "sd x10, 72(sp)\n\t"
        "sd x11, 80(sp)\n\t"
        "sd x12, 88(sp)\n\t"
        "sd x13, 96(sp)\n\t"
        "sd x14, 104(sp)\n\t"
        "sd x15, 112(sp)\n\t"
        "sd x16, 120(sp)\n\t"
        "sd x17, 128(sp)\n\t"
        "sd x18, 136(sp)\n\t"
        "sd x19, 144(sp)\n\t"
        "sd x20, 152(sp)\n\t"
        "sd x21, 160(sp)\n\t"
        "sd x22, 168(sp)\n\t"
        "sd x23, 176(sp)\n\t"
        "sd x24, 184(sp)\n\t"
        "sd x25, 192(sp)\n\t"
        "sd x26, 200(sp)\n\t"
        "sd x27, 208(sp)\n\t"
        "sd x28, 216(sp)\n\t"
        "sd x29, 224(sp)\n\t"
        "sd x30, 232(sp)\n\t"
        "sd x31, 240(sp)\n\t"

        "csrrw t0, mscratch, sp\n\t"
        "sd x2, 8(sp)\n\t"
        :
        :
        : "memory"
    );
}

static inline void restore_registers() {
    asm volatile (
        "ld x1, 0(sp)\n\t"
        "ld x3, 16(sp)\n\t"
        "ld x4, 24(sp)\n\t"
        "ld x5, 32(sp)\n\t"
        "ld x6, 40(sp)\n\t"
        "ld x7, 48(sp)\n\t"
        "ld x8, 56(sp)\n\t"
        "ld x9, 64(sp)\n\t"
        "ld x10, 72(sp)\n\t"
        "ld x11, 80(sp)\n\t"
        "ld x12, 88(sp)\n\t"
        "ld x13, 96(sp)\n\t"
        "ld x14, 104(sp)\n\t"
        "ld x15, 112(sp)\n\t"
        "ld x16, 120(sp)\n\t"
        "ld x17, 128(sp)\n\t"
        "ld x18, 136(sp)\n\t"
        "ld x19, 144(sp)\n\t"
        "ld x20, 152(sp)\n\t"
        "ld x21, 160(sp)\n\t"
        "ld x22, 168(sp)\n\t"
        "ld x23, 176(sp)\n\t"
        "ld x24, 184(sp)\n\t"
        "ld x25, 192(sp)\n\t"
        "ld x26, 200(sp)\n\t"
        "ld x27, 208(sp)\n\t"
        "ld x28, 216(sp)\n\t"
        "ld x29, 224(sp)\n\t"
        "ld x30, 232(sp)\n\t"
        "ld x31, 240(sp)\n\t"
        "ld x2, 8(sp)\n\t"

        :
        : 
        : "memory"                           
    );
}

static uint64_t lfsr(uint64_t x)
{
  uint64_t bit = (x ^ (x >> 1)) & 1;
  return (x >> 1) | (bit << 62);
}

static uintptr_t insn_len(uintptr_t pc)
{
  return (*(unsigned short*)pc & 3) ? 4 : 2;
}

#ifdef __riscv
#include "encoding.h"
#endif

#define stringify_1(s) #s
#define stringify(s) stringify_1(s)
#define stats(code, iter) do { \
    unsigned long _c = -read_csr(mcycle), _i = -read_csr(minstret); \
    code; \
    _c += read_csr(mcycle), _i += read_csr(minstret); \
    if (cid == 0) \
      printf("\n%s: %ld cycles, %ld.%ld cycles/iter, %ld.%ld CPI\n", \
             stringify(code), _c, _c/iter, 10*_c/iter%10, _c/_i, 10*_c/_i%10); \
  } while(0)

#endif //__UTIL_H
