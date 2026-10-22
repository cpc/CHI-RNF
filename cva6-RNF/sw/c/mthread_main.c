/*  Multithreaded matrix multiplication
*   
*   If the matmul succeeds, there is written "0"s to result_base [0] (and [1], if 2-core)
*/

#include "util.h"

#define N 10
#define sync_base 0x000000008007D000
#define result_base 0x000000008007E900

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile uint32_t *check_pointer = (uint32_t *) sync_base;
    volatile uint32_t *result_pointer = (uint32_t *) result_base;
    int result = 1;
    volatile int core_id = argv[0][0];
    volatile int corecount = argv[0][1];

    // the result equals 0 if the program succeeds
    result = thread_entry(core_id, corecount);

    result_pointer = result_pointer + core_id;

    ATOMIC_OP(*result_pointer, result, swap, w);

    // wait while the sync counter is the core id
    // while (*check_pointer != core_id);

    // atomic add to sync cores in the end
    ATOMIC_OP(*check_pointer, 1, add, w);
    while (*check_pointer != corecount);

    return 0;
}
