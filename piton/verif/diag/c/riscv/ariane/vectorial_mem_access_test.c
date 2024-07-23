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
// Description: Simple hello world program that prints 32 times "hello world".
//

#include <stdio.h>
#include <stdint.h>
//#include "test_macros.h"

// Test data: initialize with some known pattern
uint32_t test_data[16] __attribute__((aligned(64))) = {
	0x12345678, 0x9abcdef0, 0x0fedcba9, 0x87654321,
	0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00,
	0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
	0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20
};

// Buffer for storing results
uint32_t store_buffer[16] __attribute__((aligned(64)));

#define SIMD_COPY(SIZE,offset) asm volatile ( \
		"vsetvli x0, %2, e32, m1\n\t" \
		"vle8.v v0, (%0)\n\t" \
		"vse8.v v0, (%1)\n\t" \
		: \
		: "r" (test_data+offset), "r" (store_buffer+offset), "r" (SIZE) \
		: "v0" \
	)

// To implement all the cases we have to shift the storing address.


int check_load_store(uint32_t bytes) {
	int num_missmatches = 0;
	int num_alignments = 64/bytes;

	for(uint32_t k = 0; k < num_alignments;k++){
		for (uint32_t i = 0; i < 16; i++) {
			store_buffer[i] = 0xbadc0de; 
		}

		SIMD_COPY(bytes,k*bytes/4);

		printf("Test results (%d bytes, %d offset):\n", bytes, k*bytes);

		for (uint32_t i = 0; i < 16; i++) {
			printf("0x%08x ", store_buffer[i]);
			uint32_t good = (i >= (k*bytes/4) && i < (k+1)*bytes/4) ? test_data[i] : 0xbadc0de;
			if(store_buffer[i] != good){
					printf("Missmatch\n");
					num_missmatches++;
			}
		}

		printf("\n");
	}
	return num_missmatches;
	
}




int main(int argc, char ** argv) {

	uint8_t* msg = "TEST SUCCESSFUL";
	printf("Initialization data:\n");
	
	for (uint32_t i = 0; (i*4) < 64; i++) {
		printf("0x%08x ", test_data[i]); 
	}

	printf("\n");

	// Test
	for (int k = 8; k < 128; k = k*2) {
		if(check_load_store(k)!=0){
			printf("Test size=%d failed\n",k);
			msg = "TEST FAILED";
		}
		asm("fence");

	}

	printf("%s\n",msg);

	return 0;
}
