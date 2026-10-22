// 


#include "util.h"

#define N 200
#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

  
  volatile uint32_t coreid = argv[0][0];
  volatile uint32_t corecount = argv[0][1];
  volatile uint32_t *check_pointer = (uint32_t *) sync_base;
  volatile uint32_t *start_pointer = (uint32_t *) sync_base + 1;
  volatile uint32_t *barrier = (uint32_t *) sync_base + 2;
  volatile uint32_t *mutex = (uint32_t *) sync_base + 3;
  volatile uint32_t *result_pointer = (uint32_t *) result_base;
  //volatile uint32_t *trigger = (uint32_t *) sync_base + 15;  // THIS SHOULD BE THE EXACT ADDRESS USED FOR TRIGGERING THE COMPDATA_UDPD FROM TB

  ATOMIC_OP(*start_pointer, 1, add, w);
  while (*start_pointer != corecount){};

  /* Beginning of the program */

  volatile uint32_t temp = 1;
  static volatile uint32_t increment = 0;
      volatile uint32_t ret = 1;


  // /* Trigger the coherent stress sequence */
  // ATOMIC_OP(*trigger, 1, add, w);
  // while (*trigger != corecount){};


  /* Write 4 times to result address when data responses are reversed*/
  for (volatile uint32_t i = 0; i<N; i=i+1) {

        ret = 1;
        while(ret != 0)
        {
          LR_OP(temp, increment, w);
          temp = temp + 1;
          SC_OP(ret, increment, temp, w);
        }
  }

  // /* Barrier */
  ATOMIC_OP(*barrier, 1, add, w);
  while (*barrier != 2){};

  // /* Mutex */
  while (*mutex != coreid){};


  // result_pointer = result_base + 4;
  // ATOMIC_OP(*result_pointer, increment, swap, w);


  //result_pointer = result_base;
  if (*result_pointer != 404) {
    
    if (increment == N*corecount) {
      temp = 1;
    } else {
      temp = 404;
    }
  } else {}


  // Store '1' to the first word of the result address result was correct and to signal it to TB
  //result_pointer = result_base;
  ATOMIC_OP(*result_pointer, temp, swap, w);

  result_pointer = result_pointer + 1;
  *result_pointer = increment;

  ATOMIC_OP(*mutex, 1, add, w);


  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


