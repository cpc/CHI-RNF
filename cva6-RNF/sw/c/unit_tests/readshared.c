// ReadShared


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
  volatile uint32_t *readshared_trigger = (uint32_t *) sync_base + 15;  // THIS SHOULD BE THE EXACT ADDRESS USED FOR TRIGGERING THE READUNIQUE CHECK

  ATOMIC_OP(*start_pointer, 1, add, w);
  while (*start_pointer != corecount){};

  /* Beginning of the program */

  uint32_t temp = 0;

  /* Trigger the ReadShared check */
  ATOMIC_OP(*readshared_trigger, 1, swap, w);

  /* ReadShared to result address */
  temp = *result_pointer;

  if (temp == 0) {
    temp = temp + 1;
  } else {}

  // Store '1' to the first word of the result address result was correct and to signal it to TB
  ATOMIC_OP(*result_pointer, temp, swap, w);

  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


