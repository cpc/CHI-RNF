// Single core test for WriteBacks 


#include "util.h"

#define result_base 0x000000008007E900 // 8100 cacheline
#define result_base2 0x000000008007E940  // 8101 cacheline
#define sync_base 0x000000008007D000

#define test0 0x000000008007A900
#define test1 0x0000000080076900
#define test2 0x0000000080072900
#define test3 0x000000008006e900
#define test4 0x000000008006a900  

#define temp_base 0x000000008007A800

// argv[0][0] = core_id, argv[0][1] = corecount
int main(int argc, char ** argv) {

  
  volatile uint32_t coreid = argv[0][0];
  volatile uint32_t corecount = argv[0][1];
  volatile uint32_t *check_pointer = (uint32_t *) sync_base;
  volatile uint32_t *start_pointer = (uint32_t *) sync_base + 1;
  volatile uint32_t *result_pointer = (uint32_t *) result_base;
  volatile uint32_t *writeback_trigger = (uint32_t *) sync_base + 15;  // THIS SHOULD BE THE EXACT ADDRESS USED FOR TRIGGERING THE READUNIQUE CHECK

  ATOMIC_OP(*start_pointer, 1, add, w);
  while (*start_pointer != corecount){};

  /* Beginning of the program */

  volatile uint32_t addr = 0;
  
  for (uint32_t j = 0; j<16; j++) {
    addr = result_base + j*4;
    result_pointer = (uint32_t *) addr;
    *result_pointer = j;
  }

  for (uint32_t jj = 0; jj<16; jj++) {
    if (jj<4 | jj>11) {
      addr = result_base + 4*16 + jj*4;
      result_pointer = (uint32_t *) addr;
      *result_pointer = jj + 10000;
    } else {
      // 
    }
  }

  for (uint32_t i = 0; i<16; i++) {
      addr = result_base + 8*16 + i*4;
      result_pointer = (uint32_t *) addr;
      *result_pointer = i + 20000;
  }

  for (uint32_t ii = 0; ii<16; ii++) {
      addr = result_base + 12*16 + ii*4;
      result_pointer = (uint32_t *) addr;
      *result_pointer = ii + 30000;
  }

  // Cacheline fills so writebacks are triggered
  addr = (uint32_t *) test0;
  result_pointer = (uint32_t *) addr;
  *result_pointer = 0xbeebeeb;
  addr = (uint32_t *) test1;
  result_pointer = (uint32_t *) addr;
  *result_pointer = 0xbeebeeb;
  addr = (uint32_t *) test2;
  result_pointer = (uint32_t *) addr;
  *result_pointer = 0xbeebeeb;


  /* Trigger the WriteBack check */
  ATOMIC_OP(*writeback_trigger, 1, swap, w);

  // Trigger WriteBack with store-ack
  addr = (uint32_t *) test3;
  result_pointer = (uint32_t *) addr;
  *result_pointer = 0xbeebeeb;

  // Trigger WriteBack with AMO_SWAP
  addr = result_base + 6*16;
  result_pointer = (uint32_t *) addr;
  ATOMIC_OP(*result_pointer, 11111, swap, w);

  // Trigger WriteBackFull with AMO_SWAP
  addr = result_base + 8*16;
  result_pointer = (uint32_t *) addr;
  ATOMIC_OP(*result_pointer, 33333, swap, w);

  // Trigger WriteBack with LR
  volatile uint32_t ret = 0;
  addr = result_base + 12*16;
  result_pointer = (uint32_t *) addr;
  LR_OP(ret, *result_pointer, w);


  // Checks
  volatile uint32_t addr2 = result_base + 4*3;
  result_pointer = (uint32_t *) addr2;

  if (*result_pointer == 3) { // Check 1st wb
    // Store '1' to the first word of the result address result was correct and to signal it to TB
    result_pointer = (uint32_t *) result_base;
    ATOMIC_OP(*result_pointer, 1, swap, w);

    addr2 = result_base + 4*16;
    result_pointer = (uint32_t *) addr2;

    if (*result_pointer == 10000) { // Check 3rd wb
      // Store '1' to the first word of the result address result was correct and to signal it to TB
      result_pointer = (uint32_t *) result_base;
      ATOMIC_OP(*result_pointer, 1, swap, w);

      addr2 = result_base + 8*16;
      result_pointer = (uint32_t *) addr2;

      if (*result_pointer == 33333) { // Check 3rd wb
        // Store '1' to the first word of the result address result was correct and to signal it to TB
        result_pointer = (uint32_t *) result_base;
        ATOMIC_OP(*result_pointer, 1, swap, w);

        addr2 = result_base + 12*16;
        result_pointer = (uint32_t *) addr2;

        if (*result_pointer == 30000) { // Check 4th wb
          // Store '1' to the first word of the result address result was correct and to signal it to TB
          result_pointer = (uint32_t *) result_base;
          ATOMIC_OP(*result_pointer, 1, swap, w);
        } else {
          result_pointer = (uint32_t *) result_base;
          ATOMIC_OP(*result_pointer, 404, swap, w);
        }

      } else {
        result_pointer = (uint32_t *) result_base;
        ATOMIC_OP(*result_pointer, 404, swap, w);
      }

    } else {
      result_pointer = (uint32_t *) result_base;
      ATOMIC_OP(*result_pointer, 404, swap, w);
    }

  } else {
    result_pointer = (uint32_t *) result_base;
    ATOMIC_OP(*result_pointer, 404, swap, w);
  }


  /* End of the program*/
  ATOMIC_OP(*check_pointer, 1, add, w);
  while (*check_pointer != corecount){};

  return 0;
}


