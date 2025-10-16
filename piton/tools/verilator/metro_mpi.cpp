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

#include <iostream>
#include <mpi.h>
#include <vector>
#include <cstring>
#include "metro_mpi.h"

using namespace std;



int mpi_check_trap (int local_condition){    
    int global_condition = CONTINUE; // Global exit condition after reduction
    // Use MPI_Allreduce to find the maximum exit condition across all processes
    MPI_Allreduce(&local_condition, &global_condition, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
    return global_condition;
}





void initialize(){
    MPI_Init(NULL, NULL);
    //cout << "initializing" << endl;
}

int getRank(){
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    return rank;
}

int getSize(){
    int size;
    MPI_Comm_rank(MPI_COMM_WORLD, &size);
    return size;
}

void finalize(){
    //cout << "[DPI CPP] Finalizing" << endl;
    MPI_Finalize();
}




// MPI finish functions
unsigned short mpi_receive_finish(){
    unsigned short message;
    int message_len = 1;
    //cout << "[DPI CPP] Block Receive finish from rank: " << origin << endl << std::flush;
    MPI_Bcast(&message, message_len, MPI_UNSIGNED_SHORT, 0, MPI_COMM_WORLD);
    /*if (short(message)) {
        cout << "[DPI CPP] finish received: " << std::hex << (short)message << endl << std::flush;
    }*/
    return message;
}

void mpi_send_finish(unsigned short message, int rank){
    int message_len = 1;
    /*if (message) {
        cout << "[DPI CPP] Sending finish " << std::hex << (int)message << " to All" << endl << std::flush;
    }*/
    MPI_Bcast(&message, message_len, MPI_UNSIGNED_SHORT, rank, MPI_COMM_WORLD);
}


void mpi_send_chan(void * chan, size_t len, int dest, int rank, int flag){
 // printf("send dest %u, rank=%u, flag=%u\n dat=0X",dest,rank,flag);
  //char * ch = (char *) chan;
  //for(int i=0; i<len; i++) printf("%X", ch[i]);
 // printf("\n");
  MPI_Send(chan, len,MPI_CHAR, dest, flag, MPI_COMM_WORLD);
}

void mpi_receive_chan(void * chan, size_t len, int origin, int flag){
    MPI_Status status;
    char * ch = (char *) chan;
    MPI_Recv(chan, len, MPI_CHAR, origin, flag, MPI_COMM_WORLD, &status);
    return;
    /*
    printf("MPI process received  from rank %d, with tag %d and error code %d.\n",                status.MPI_SOURCE,
                  status.MPI_TAG,
                  status.MPI_ERROR);
    printf("got origin%u, flag=%u\n dat=0X\n",origin,flag);

    for(int i=0; i<len; i++) printf("%X\n",  ch[i]);
    printf("\n");
    */
}


void print_static (MEM_STAT_t stat, uint64_t ticks){
    if (stat.mc_num==-1){
    std::cout<<"chipset, ";
    }else{
    std::cout << stat.mc_num << ", ";
}
    std::cout
     << stat.rank << ", "
     << stat.dest << ", "
     << stat.flit_in_num  << ", "
     << stat.flit_out_num  << ", "
     << ticks << ", "
     << ticks/500  << ", " << std::endl;
}


string get_mem_image_full_path (int argc, char **argv){
	vector<string> args(argv + 1, argv + argc);
	vector<string>::iterator tail_args = args.end();
	string path = "./";
	for(vector<string>::iterator it = args.begin(); it != args.end(); ++it) 
	{
	    if(it->find("+mem_image=") == 0) {
	       path=it->substr(strlen("+mem_image="));
	      // std::cout << "****************************" << path << "****************";
	    }   
	}
	return path;
}


string get_lat_model_full_path (int argc, char **argv){
	vector<string> args(argv + 1, argv + argc);
	vector<string>::iterator tail_args = args.end();
	string path = "./";
	for(vector<string>::iterator it = args.begin(); it != args.end(); ++it) 
	{
	    if(it->find("+lat_model=") == 0) {
	       path=it->substr(strlen("+lat_model="));
	    //   std::cout << "*******lat model*********************" << path << "****************";
	    }   
	}
    
	return path;
}

vector<uint64_t> get_traps (int argc, char **argv,bool type){ 
    vector<string> args(argv + 1, argv + argc);
	vector<string>::iterator tail_args = args.end();
    vector<uint64_t> trap;
    string st;  
    std::string trap_str;  
    for(vector<string>::iterator it = args.begin(); it != args.end(); ++it) 
	{
	   for (int i=0; i<32;i++){
        if (type==GOOD_TRAP) trap_str = "+good_trap" + std::to_string(i) + "=";
        else trap_str = "+bad_trap" + std::to_string(i) + "=";
       //std::cout <<  trap_str << std::endl;
       if(it->find(trap_str) == 0) {
	       st=it->substr(trap_str.length());
	        try {
                    // Convert st to uint64_t and push to the vector
                    uint64_t trap_value =  std::stoull(st, nullptr, 16);
                    trap.push_back(trap_value);
                    //printf("push %lx\n",trap_value);
                } catch (const std::invalid_argument& e) {
                    cerr << "Invalid number: " << st << endl;
                } catch (const std::out_of_range& e) {
                    cerr << "Number out of range: " << st << endl;
            }
	    }   
       }
	}
    return trap; 
}

HPM_STRING
