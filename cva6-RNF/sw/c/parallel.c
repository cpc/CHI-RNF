#include "util.h"

#define N 10
#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000
#define coreid_base 0x000000008000FA00

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile uint32_t core_id = argv[0][0];
    volatile uint32_t corecount = argv[0][1];
    volatile uint32_t *check_pointer = (int *) sync_base;
    volatile uint32_t *coreid_pointer = (int *) coreid_base;
    volatile uint32_t *sync_pointer = (int *) sync_base + 16;
    volatile uint32_t *results_p = (int *) result_base; // 0x0000000080007D00: cacheline 500 (500x64byte = addr:7D00)
    volatile static uint32_t tmp = 0;
    volatile uint32_t local_tmp = 0;


    results_p = results_p + core_id*2;
    coreid_pointer = coreid_pointer + core_id; 

    ATOMIC_OP(*results_p, core_id, add, w);
    ATOMIC_OP(*coreid_pointer, core_id, add, w);

    results_p = results_p + 1; 

    // "mutex"
    while (*sync_pointer != core_id){};

    for (int i = 0; i<N; i++){

        local_tmp = local_tmp + 5;

    }


    // // "mutex"
    // while (*sync_pointer != core_id){};

    local_tmp = tmp + local_tmp;
    tmp = local_tmp;

    ATOMIC_OP(*results_p, tmp, add, w);

    // "release the mutex", atomic add to sync cores in the end
    ATOMIC_OP(*sync_pointer, 1, add, w);



    // "mutex"
    while (*check_pointer != core_id){};
    // atomic add to sync cores in the end
    ATOMIC_OP(*check_pointer, 1, add, w);


  return 0;
}