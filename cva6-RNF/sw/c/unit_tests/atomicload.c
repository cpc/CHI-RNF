// RNF AtomicLoad test sequence


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

  uint32_t ones = 4294967295;
  uint32_t zeros = 0;
  uint32_t onesnzeros = 4294901760;
  uint32_t zerosnones = 65535;

  ATOMIC_OP(*result_pointer, 1, add, w);

  result_pointer = result_pointer + 1;

  // 1: AMO add xFFFF0000
  ATOMIC_OP(*result_pointer, onesnzeros, add, w);

  
  result_pointer = result_pointer + 1;

  // 2: AMO add xFFFFFFFF, AMO and xFFFF0000
  ATOMIC_OP(*result_pointer, ones, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, and, w);

  result_pointer = result_pointer + 1;

  // 3: AMO or xFFFF0000
  ATOMIC_OP(*result_pointer, zeros, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, or, w);

  result_pointer = result_pointer + 1;

  // 4: AMO add x0, AMO xor xFFFF0000
  ATOMIC_OP(*result_pointer, zeros, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, xor, w);

  result_pointer = result_pointer + 1;

  // 5: AMO add x0, AMO max xFFFF0000
  ATOMIC_OP(*result_pointer, zeros, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, max, w);

  result_pointer = result_pointer + 1;

  // 6: AMO add xFFFF0000, AMO min x0F
  ATOMIC_OP(*result_pointer, onesnzeros, add, w);
  ATOMIC_OP(*result_pointer, ones, min, w);

  result_pointer = result_pointer + 1;

  // 7: AMO add x0000FFFF, AMO maxu xFFFF0000
  ATOMIC_OP(*result_pointer, zerosnones, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, maxu, w);

  result_pointer = result_pointer + 1;
  
  // 8: AMO add xFFFFFFFF, AMO minu xFFFF0000
  ATOMIC_OP(*result_pointer, ones, add, w);
  ATOMIC_OP(*result_pointer, onesnzeros, minu, w);



  volatile uint32_t addr = result_base + 4;
  result_pointer = (uint32_t *) addr;

  // Check the results
  for (int i = 0; i<8; i=i+1){
    if (*result_pointer != onesnzeros) {
      addr = result_base;
      result_pointer = (uint32_t *) addr;
      ATOMIC_OP(*result_pointer, 404, swap, w);
      break;
    } else {
      result_pointer = result_pointer + 1;
    }
  }


  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


