// Tests LR/SC pairs and makes sure the rest of the cacheline is unaffected
// Use `sims ... -gcc_args=-DENABLE_DEBUG_PRINTS` to enable debugging prints.
// Written by: Arnau Bigas <arnau.bigas@bsc.es>

#include <stdio.h>
#include <stdint.h>
#include "util.h"

// Cacheline size in bytes
#define CACHELINE_BYTES 64

#ifdef ENABLE_DEBUG_PRINTS
#define DEBUG_LOG(fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#define DEBUG_LOG
#endif
#define ERROR_LOG(fmt, ...) printf(fmt, ##__VA_ARGS__)

#define MAGIC_DATA 0xdeadbeefL

// Test data: initialize with some known pattern
uint32_t test_data[CACHELINE_BYTES/4] __attribute__((aligned(CACHELINE_BYTES)));

// Test data: initialize with some known pattern
uint32_t golden_reference[CACHELINE_BYTES/4] __attribute__((aligned(CACHELINE_BYTES))) = {
	0x12345678, 0x9abcdef0, 0x0fedcba9, 0x87654321,
	0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00,
	0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
	0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20
};

// Copies the golden_reference into test_data
static inline void setup_cacheline() {
	for (unsigned int i = 0; i < (CACHELINE_BYTES/4); i++) {
		test_data[i] = golden_reference[i];
	}
}

// Performs an lr/sc pair in test_data[index], at word size or double size
// depending on is_double. Writes a magic value '0xdeadbeef' at index.
// Returns 1 if the lr/sc failed.
static inline unsigned int lrsc(unsigned int index, unsigned int is_double) {
    uint32_t tmp = 1;
	if (is_double) {
		LR_OP(tmp, test_data[index], d);
		SC_OP(tmp, test_data[index], (MAGIC_DATA << 32) | MAGIC_DATA, d);
	} else {
		LR_OP(tmp, test_data[index], w);
		SC_OP(tmp, test_data[index], MAGIC_DATA, w);
	}
    return tmp != 0;
}


// Compares the test_data with golden_reference, and looks for the magic value
// at index. Fails if the test_data doesn't match the golden_reference or if
// the magic value is not in the index.
static inline unsigned int check_cacheline(unsigned int index, unsigned int is_double) {
	unsigned int error = 0;
	for (unsigned int i = 0; i < (CACHELINE_BYTES/4); i++) {
		const unsigned int expected =
			(i == index || (is_double && ((i-1) == index))) ? MAGIC_DATA
															: golden_reference[i];

		const unsigned int mismatch = test_data[i] != expected;
		error |= mismatch;

		if (mismatch) DEBUG_LOG("Mismatch at index %d: expected=%x test_data=%x\n", index, expected, test_data[i]);
	}
	return error;
}

int main(int argc, char ** argv) {

	unsigned int total_mismatches = 0;
	unsigned int total_tests = 0;

	// For loop to test word and double sizes
	for (unsigned int is_double = 0; is_double < 2; is_double++) {
		if (is_double) DEBUG_LOG("Testing lr.d & sc.d\n");
		else DEBUG_LOG("Testing lr.w & sc.w\n");

		// Test each index of a single cacheline
		for (unsigned int i = 0; i < (CACHELINE_BYTES/4); is_double ? i+=2 : i++) {
			unsigned int error = 0;

			setup_cacheline();

			error |= lrsc(i, is_double); // Flag error if sc wasn't successful

			error |= check_cacheline(i, is_double); // Flag error if memcheck fails

			if (error) {
				DEBUG_LOG("Error when testing lrsc (is_double? %d) at index %d.\n", is_double, i);
			}

			total_mismatches += error;
			total_tests += 1;
		}
	}

	if (total_mismatches > 0) {
		ERROR_LOG("TEST FAILED: %d mismatches out of %d tests\n", total_mismatches, total_tests);
	} else {
		ERROR_LOG("TEST PASSED\n");
	}

	return total_mismatches;
}
