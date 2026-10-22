// WriteNoSnp


#include "util.h"

#define result_base 0x000000008007E900
#define sync_base 0x000000008007D000
#define io_base 0x000000FFF0C2C000

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

  
  volatile uint32_t coreid = argv[0][0];
  volatile uint32_t corecount = argv[0][1];
  volatile uint32_t *check_pointer = (uint32_t *) sync_base;
  volatile uint32_t *start_pointer = (uint32_t *) sync_base + 1;
  volatile uint32_t *result_pointer = (uint32_t *) result_base;
  volatile uint64_t *io_pointer = (uint64_t *) io_base;
  volatile uint32_t *writenosnp_trigger = (uint32_t *) sync_base + 15;

  ATOMIC_OP(*start_pointer, 1, add, w);
  while (*start_pointer != corecount){};

  /* Beginning of the program */

  volatile uint64_t addr = 0;

  /* Trigger writenosnp */
  ATOMIC_OP(*writenosnp_trigger, 1, swap, w);

  // 10 noncacheable writes
  for ( uint64_t i=0; i<10; i++) {
    addr = io_base + i*8;
    io_pointer = (uint64_t *) addr;
    *io_pointer = i;
  }

  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


