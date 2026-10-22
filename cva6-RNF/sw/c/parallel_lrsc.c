#include "util.h"

#define N 10
#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile uint32_t core_id = argv[0][0];
    volatile uint32_t *check_pointer = (int *) sync_base;
    volatile uint32_t *sync_pointer = (int *) sync_base + 16;
    volatile uint32_t *results_p = (int *) result_base; // 0x0000000080007D00: cacheline 500 (500x64byte = addr:7D00)
    volatile int ret = 0;
    volatile uint32_t local_tmp = 0;


    results_p = results_p + core_id; 

    ATOMIC_OP(*results_p, core_id, add, w);

    results_p = (int *) result_base + 2; 

    for (uint32_t i = 0; i<N; i++){

        ret = 1;
        while(ret != 0)
        {
            LR_OP(ret, *results_p, w);
            local_tmp = ret + 5;
            SC_OP(ret, *results_p, local_tmp, w);
        }

    }
    // to get the last value written to LLC 
    LR_OP(ret, *results_p, w);
    //ATOMIC_OP(*results_p, local_tmp, add, w);

    // "mutex"
    while (*check_pointer != core_id){};
    // atomic add to sync cores in the end
    ATOMIC_OP(*check_pointer, 1, add, w);

    while (*check_pointer != argv[0][1]){};

  return 0;
}