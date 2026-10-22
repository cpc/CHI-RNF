// Atomic ADD and SWAP RNF-test


#include "util.h"

#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

  
  volatile uint32_t coreid = argv[0][0];
  volatile uint32_t corecount = argv[0][1];
  volatile uint32_t *check_pointer = (uint32_t *) sync_base;
  volatile uint32_t *start_pointer = (uint32_t *) sync_base + 1;
  volatile uint32_t *result_pointer = (uint32_t *) result_base;

  ATOMIC_OP(*start_pointer, 1, add, w);
  while (*start_pointer != corecount){};

  /* Beginning of the program */

  volatile uint32_t temp = 1;

  result_pointer = result_pointer + 1;
  
  // AtomicLoad Add
  ATOMIC_OP(*result_pointer, temp, add, w);

  result_pointer = result_pointer + 1;

  // AtomicSwap
  ATOMIC_OP(*result_pointer, temp, swap, w);

  temp = *result_pointer;

  result_pointer = result_pointer - 1;

  temp = temp + *result_pointer;

  result_pointer = (uint32_t *) result_base;

  // Result check
  if (temp == 2) {
    temp = temp + 1;
    ATOMIC_OP(*result_pointer, 1, swap, w);
  } else {
    ATOMIC_OP(*result_pointer, 404, swap, w);
  }


  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


