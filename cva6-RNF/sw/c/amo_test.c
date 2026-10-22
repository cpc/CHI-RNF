
// #include <stdint.h>
// #include <stdio.h>
#include "util.h"

#define N 10
#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile int *check_pointer = (int *) sync_base;

    volatile uint32_t *results_p = (int *) result_base; // 0x0000000080007D00: cacheline 500 (500x64byte = addr:7D00)
    uint32_t result_address = 0;
    uint32_t results[N] = {0};
    uint32_t retval = 0;
    uint32_t ones = 0b01111111111111111111111111111111;
    uint32_t zeros = 0;
    uint32_t onesnzeros = 0b01110000111100001111000011110000;
    uint32_t zerosnones = 0b00001111000011110000111100001111;
    uint32_t tmp = 0;
    uint32_t ret = 0;
    uint32_t result = 0;

    volatile int *test_p = (int *) 0x0000000080003D00;
    *test_p = argv[0][0];

    results_p = results_p + argv[0][0]*16;

    // AMO add xFFFF, AMO and xF0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, onesnzeros, and, w);

    results_p = results_p + 1;

    // AMO or 
    ATOMIC_OP(*results_p, zeros, add, w);
    ATOMIC_OP(*results_p, zerosnones, or, w);

    results_p = results_p + 1;

    // AMO add FFFF, AMO xor F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, onesnzeros, xor, w);

    results_p = results_p + 1;

    // AMO add FFFF, AMO max F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, zerosnones, max, w);

    results_p = results_p + 1;

    // AMO add FFFF, AMO min F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, zerosnones, min, w);

    results_p = results_p + 1;

    // AMO add FFFF, AMO maxu F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, zerosnones, maxu, w);

    results_p = results_p + 1;
    
    // AMO add FFFF, AMO minu F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, zerosnones, minu, w);

    results_p = results_p + 1;
    
    // AMO add FFFF, AMO minu F0F0
    ATOMIC_OP(*results_p, ones, add, w);
    ATOMIC_OP(*results_p, onesnzeros, swap, w);

    // wait while the sync counter is the core id
    while (*check_pointer != argv[0][0]);

    results_p = results_p + 1;

    if (argv[0][0] != 0) {
      results_p = results_p - argv[0][0]*16;
      tmp = *results_p;
      results_p = results_p + argv[0][0]*16;

      ATOMIC_OP(*results_p, tmp, add, w);
    }

    // LRSC
    for (int i=0; i<N; i++)
    {
      tmp = 1;
      while(tmp != 0)
      {
              LR_OP(tmp, *results_p, w);
              result = tmp + 1;
              SC_OP(tmp, *results_p, result, w);
      }
      LR_OP(tmp, *results_p, w);
    }

    // to get the last value written to LLC 

    // atomic add to sync cores in the end
    ATOMIC_OP(*check_pointer, 1, add, w);

  return 0;
}
