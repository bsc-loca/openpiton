typedef int (*func_ptr_t)();

int function[] = {
    0x00100513, // li a0, 1
    0x00008067, // ret
};

int main(int argc, char ** argv) {
    func_ptr_t fn = (func_ptr_t) function;
    int result;

    // Run initial version of the function, check result
    if (fn() != 1) return 1;

    // Modify the function to change the result
    function[0] = 0x00200513; // li a0, 2

    // Wait a few cycles to make sure the changes are propagated, icache invalidated, etc
    for (int i = 0; i < 10; i++) __asm__ ("nop");

    // Check the result, to make sure the correct (modified) code is being run instead of the old stale code
    if (fn() != 2) return 1;

    return 0;
}
