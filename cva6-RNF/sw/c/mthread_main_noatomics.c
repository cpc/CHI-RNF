/* Multithreaded matrix multiplication using LR/SC
* * If the matmul succeeds, there is written "0"s to result_base [0] (and [1], if 2-core)
*/

#include "util.h"

#define N 10
#define sync_base 0x000000008007D000
#define result_base 0x000000008007E900

int main(int argc, char ** argv) {

    volatile uint32_t *check_pointer = (uint32_t *) sync_base;
    volatile uint32_t *result_pointer = (uint32_t *) result_base;
    int result = 1;
    volatile int core_id = argv[0][0];
    volatile int corecount = argv[0][1];

    // the result equals 0 if the program succeeds
    result = thread_entry(core_id, corecount);

    result_pointer = result_pointer + core_id;

    // --- REPLACING ATOMIC SWAP ---
    // Atomic Swap: *result_pointer = result
    uint32_t tmp_val, status;
    __asm__ __volatile__ (
        "1: lr.w.aq %0, (%2)      \n" // Load reserved with acquire
        "   sc.w.rl %1, %3, (%2)  \n" // Store conditional with release
        "   bnez    %1, 1b        \n" // Retry if sc failed (status != 0)
        : "=&r" (tmp_val), "=&r" (status)
        : "r" (result_pointer), "r" (result)
        : "memory"
    );

    // --- REPLACING ATOMIC ADD ---
    // Atomic Add: *check_pointer = *check_pointer + 1
    uint32_t current_sync;
    __asm__ __volatile__ (
        "1: lr.w.aq %0, (%2)      \n" // Load reserved
        "   addi    %0, %0, 1     \n" // Increment locally
        "   sc.w.rl %1, %0, (%2)  \n" // Store conditional
        "   bnez    %1, 1b        \n" // Retry if failed
        : "=&r" (current_sync), "=&r" (status)
        : "r" (check_pointer)
        : "memory"
    );

    // Final barrier: Wait until all cores have checked in
    while (*check_pointer != corecount);

    return 0;
}