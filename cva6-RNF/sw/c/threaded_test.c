
#include "util.h"
//#include "sync_thread.h"

#define N 30
#define result_base 0x0000000080007D00
#define mutex_base 0x000000008000FA00
#define sync_base 0x000000008003FFC0


    volatile static uint32_t mutex0 = 0;
    volatile static uint32_t barrier0 = 0;



volatile void sync_mutex_lock(uint32_t *m) {
    volatile uint32_t l = 0;
    volatile uint32_t ret = 0;


    // while (*m != 0){};
    // ATOMIC_OP(*m, 1, swap, w);


    while (l == 1 || ret != 0){
        LR_OP(l, *m, w);
        if (l == 0) {
            SC_OP(ret, *m, 1, w);
        }
    }
}

volatile void sync_mutex_release(uint32_t *m){
    volatile uint32_t ret = 0;

    //ATOMIC_OP(*m, 0, swap, w);


    while (ret != 0){
        LR_OP(ret, m, w);
        SC_OP(ret, m, 0, w);
    }
}


void sync_barrier(uint32_t coreid) {



}




int calc(int id) {
    volatile int *results_p = (int *) result_base; // 0x0000000080007D00: cacheline 500 (500x64byte = addr:7D00)
    results_p = results_p + id;

    int res = 1 + id;
    ATOMIC_OP(*results_p, res, add, w);
    
    return res;
}


int thread_entry(int (*function)(int), int coreid){

    int result = function(coreid);

    if (result == coreid+1) {
        return 0;
    }

    return 1;

}





// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

    volatile int *check_pointer = (int *) sync_base;
    volatile char coreid = argv[0][0];
    volatile char corecount = argv[0][1];


    /*toimiva*/
    while (mutex0 != coreid){};





    //sync_mutex_lock(&mutex0);

    int val = thread_entry(calc, coreid);

    //sync_mutex_release(&mutex0);





    /*toimiva*/
    ATOMIC_OP(mutex0, 1, add, w);


    while (*check_pointer != coreid){};
    ATOMIC_OP(*check_pointer, 1, add, w);

    ATOMIC_OP(barrier0, 1, add, w);
    while (barrier0 != corecount){};

  return 0;
}
