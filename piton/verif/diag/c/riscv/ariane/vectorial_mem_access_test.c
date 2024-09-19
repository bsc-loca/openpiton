// Tests write-throughs to memory using a vector unit and vector copies.
// Use `sims ... -gcc_args=-DENABLE_DEBUG_PRINTS` to enable debugging prints.
// Written by: Arnau Bigas <arnau.bigas@bsc.es>
//             Joaquim Borras <joaquim.borras@bsc.es>

#include <stdio.h>
#include <stdint.h>

// Cacheline size in bytes
#define CACHELINE_BYTES 64

// Vector element size in bytes -- this will determine the alignment of the accesses
#define ELEMENT_SIZE_BYTES 4
#define ELEMENT_SIZE_BITS 32 // Must be hardcoded in order to perform stringification

#define xstr(a) str(a)
#define str(a) #a

#ifdef ENABLE_DEBUG_PRINTS
#define DEBUG_LOG(fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#define DEBUG_LOG
#endif
#define ERROR_LOG(fmt, ...) printf(fmt, ##__VA_ARGS__)

// Test data: initialize with some known pattern
uint32_t test_data[CACHELINE_BYTES/4] __attribute__((aligned(CACHELINE_BYTES))) = {
	0x12345678, 0x9abcdef0, 0x0fedcba9, 0x87654321,
	0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00,
	0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
	0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20
};

// Buffer for storing results
uint32_t store_buffer[CACHELINE_BYTES/4] __attribute__((aligned(CACHELINE_BYTES)));

// This configures the Vector Unit to have a vector length of size SIZE and of
// 4-byte elements (words).
#define SIMD_COPY(SIZE, offset, vector_length) asm volatile ( \
		"vsetvli %0, %3, e8, m1, ta\n\t" \
		"vle8.v v0, (%1)\n\t" \
		"vse8.v v0, (%2)\n\t" \
		: "=r" (vector_length) \
		: "r" (test_data+offset), "r" (store_buffer+offset), "r" (SIZE) \
		: "v0" \
	)

// Returns 1 if there is an error unrelated to the test (i.e. SIMD unit not wide enough)
unsigned int check_load_store(const unsigned int bytes, unsigned int *test_count, unsigned int *failed_count) {
	// Calculate number of possible alignments, taking into account cache line
	// boundaries. E.g. with 4 byte elements, vector lengths of 1 element will
	// have 64/4=16 possibilities, but with 2 elements (i.e. 8 bytes), there
	// will be 15, as the last 4-byte offset would overrun and access the next
	// cacheline.
	const unsigned int num_alignments = CACHELINE_BYTES/ELEMENT_SIZE_BYTES
		- (bytes > ELEMENT_SIZE_BYTES ? (bytes/ELEMENT_SIZE_BYTES)-1 : 0);

	*test_count = num_alignments;
	*failed_count = 0;

	// Check all possible alignments for the access (i.e. if testing 16B stores
	// in 64B cachelines, there are 16/64=4 possible alignments).
	for(uint32_t alignment_offset = 0; alignment_offset < num_alignments; alignment_offset++){

		// Initialize store buffer with known data
		for (uint32_t offset = 0; offset < 16; offset++) {
			store_buffer[offset] = 0xbadc0de; 
		}

		// Perform test (copy from test data to store buffer)
		unsigned int vector_length = 0;
		SIMD_COPY(bytes, alignment_offset, vector_length);
		if(vector_length != bytes) return 1;

		DEBUG_LOG("Test results (%d bytes, %d offset):\n", bytes, alignment_offset*bytes);

		unsigned int failed = 0;
		unsigned int write_start = alignment_offset*ELEMENT_SIZE_BYTES/4;
		unsigned int write_end = write_start + (bytes/4);

		// Check the written data word by word
		for (uint32_t word_offset = 0; word_offset < 16; word_offset++) {
			DEBUG_LOG("0x%08x ", store_buffer[word_offset]);

			// The word is within the written region if the word_offset is
			// within the current alignment offset and the next
			unsigned int should_be_written = word_offset >= write_start && word_offset < write_end;

			// If the current word offset should have been written, compare it
			// against the test data. If it should have stayed the same, compare
			// it against the initialization data.
			uint32_t good = should_be_written ? test_data[word_offset] : 0xbadc0de;

			// Based on the previous variables, if there is a mismatch, report it.
			if(store_buffer[word_offset] != good){
					DEBUG_LOG("(mismatch) ");
					failed = 1; // Flag that this alignment has had at least one mismatch
			}
		}

		// If any of the words mismatched, flag alignment test as failed
		if (failed) (*failed_count)++;

		DEBUG_LOG("\n");
	}

	return 0;
}

int main(int argc, char ** argv) {

	unsigned int total_mismatches = 0;
	unsigned int total_tests = 0;
	unsigned int test_error = 0;

	DEBUG_LOG("Initialization data:\n");
	for (uint32_t i = 0; (i*4) < 64; i++) {
		DEBUG_LOG("0x%08x ", test_data[i]); 
	}
	DEBUG_LOG("\n");

	// Run test with all supported configuration sizes.
	// SIMD Unit in Sargantana is 128 bits
	for (int bits = 32; bits <= 128; bits = bits*2) {
		unsigned int test_count = 0;
		unsigned int test_mismatches = 0;

		if (check_load_store(bits/8, &test_count, &test_mismatches)) {
			ERROR_LOG("Error: Configuration with %d bits not supported\n", bits);
			test_error = 1;
			return 1;
		}

		total_tests += test_count;
		total_mismatches += test_mismatches;

		if(test_mismatches != 0){
			ERROR_LOG("Test size=%dB failed (%d mismatches, %d tests)\n", bits/8, test_mismatches, test_count);
		} else {
			ERROR_LOG("Test size=%dB passed (%d tests)\n", bits/8, test_count);
		}

		asm("fence");
	}

	if (total_mismatches > 0) {
		ERROR_LOG("TEST FAILED: %d mismatches out of %d tests\n", total_mismatches, total_tests);
	} else {
		ERROR_LOG("TEST PASSED\n");
	}

	return total_mismatches;
}
