/*
 * Copyright (c) 2024, Barcelona Supercomputing Center
 * Contact: pouya.esmaili    [at] bsc [dot] es
 *          alireza.monemi   [at] bsc [dot] es
 *          petar.radojkovic [at] bsc [dot] es
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

#include <stdio.h>
#include <string>	
	
#include <stdint.h> // for uint32_t

#include "bw_lat_mem_ctrl.h"


// 1 highest bw. The biffet the lower bw
#define ISSUE_INTENSITY 1

using namespace std;

// each tick is for cycle. 
// just for playing. i do not know the number. 
uint64_t tick(uint64_t cycle)
{
	return cycle + ISSUE_INTENSITY;
}




int main() {
    char filename[] = "./sims.log"; // Replace with your input file name
    FILE *file = fopen(filename, "r");
    
    if (file == NULL) {
        printf("Error opening file '%s'\n", filename);
        return 1;
    }
    
    char line[100];
    while (fgets(line, sizeof(line), file)) {
        int is_rd = 0;
        int is_wr = 0;
        int num_value = 0;
        
        if (sscanf(line, "RD=%d", &num_value) == 1) {
            is_rd = 1;
        } else if (sscanf(line, "WR=%d", &num_value) == 1) {
            is_wr = 1;
        }
        
        printf("Line: %s\n", line);
        printf("Is RD: %d\n", is_rd);
        printf("Is WR: %d\n", is_wr);
        printf("Number: %d\n\n", num_value);
    }
    
    fclose(file);
    return 0;
}




int main1() {
	string myAddress("./cxl-curve");
	uint32_t lat1, lat2, lat3, lat4;	

	// initialize cycles
	uint64_t cycle=0;


	// creating the memory instance
	BwLatMemCtrl* bwLatMemCtrl = new BwLatMemCtrl(myAddress, 1000, 50, 1.5);


	


	// access has two inputs (1) cycle, (2) isWrite 0: read 1: wirte
	
	// sending writes 
	for (int i = 0; i < 1200; ++i)
	{
		bwLatMemCtrl->access(cycle,1);
		cycle = tick(cycle);
	}

	// sending reads
	for (int i = 0; i < 1200; ++i)
	{
		lat1 = bwLatMemCtrl->access(cycle,0);
		cycle = tick(cycle);
	}
	
	cout << "latency from function: " << lat1 <<  endl;



	return 0;
}
