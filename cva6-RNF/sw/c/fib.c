
// #include <stdint.h>
// #include <stdio.h>
#include "util.h"

#define N 50
#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile int *check_pointer = (int *) sync_base;
    volatile uint32_t *results_p = (uint32_t *) result_base; // 0x0000000080007D00: cacheline 500 (500x64byte = addr:7D00)
    uint32_t result_address = 0;
    uint32_t results[N] = {0};
    uint32_t retval = 0;
    uint32_t a1 = 0;
    uint32_t a2 = 0;

    volatile uint32_t *test_p = (uint32_t *) 0x0000000080003D00;
    volatile uint32_t *test_array = (uint32_t *) test_p;
    *test_p = argv[0][0];


    // end loop according to core id and corecount
    for(int n=((N/argv[0][1])*argv[0][0]); n<(N/argv[0][1]+((N/argv[0][1])*argv[0][0])); n = n+1)
    {
        result_address = result_base + n*4;
        results_p = (uint32_t *) result_address;
        test_p = test_p + n*4;

        if (n <= 1) {
        results[n] = n;
        ATOMIC_OP(*results_p, n, add, w);
        }
        else {
        a1 = 0;
        a2 = 1;
        for (int i=0; i<n-1; ++i)
        {
            retval = a1+a2;
            a1 = a2;
            a2 = retval;
        }
        results[n] = retval;

        *test_p = retval;

        ATOMIC_OP(*results_p, retval, add, w);
        }
    }


    while (*check_pointer != argv[0][0]){};
    ATOMIC_OP(*check_pointer, 1, add, w);

  return 0;
}
