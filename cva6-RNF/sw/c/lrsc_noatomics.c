#include <stdint.h>
#include <stdio.h>
#include "util.h"

#define ITERATION 10

// Helper function to perform an atomic add using LR/SC only
// This replaces the AMOs like amoadd.w
void lrsc_add(volatile uint32_t *addr, uint32_t delta) {
    uint32_t tmp, status;
    do {
        LR_OP(tmp, *addr, w);      // Load Reserved
        tmp = tmp + delta;         // Calculate new value
        SC_OP(status, *addr, tmp, w); // Store Conditional
    } while (status != 0);         // In RISC-V, SC returns 0 on success
}

int main(int argc, char** argv) {
  // Use volatile to ensure the compiler doesn't optimize away polling loops
  volatile static uint32_t amo_cnt[20];
  volatile static uint32_t amo_lrsc[20];

  uint32_t id, core_num;
  int i;

  id = argv[0][0];
  core_num = argv[0][1];

  // Initialization (only core 0 clears the shared vars)
  if(id == 0) {
    amo_cnt[0] = 0;
    amo_lrsc[0] = 0;
    for (i = 1; i < 20; i++) {
        lrsc_add(&amo_cnt[i], 1);
        lrsc_add(&amo_lrsc[i], 1);
    }
  }

  // 1. Barrier: Wait for core's turn
  while(id != amo_cnt[0]);

  // 2. Increment sync counter using LR/SC instead of ATOMIC_OP
  lrsc_add(&amo_cnt[0], 1);

  // 3. Barrier: Wait for all cores to reach this point
  while(core_num != amo_cnt[0]);

  // 4. Main Test Section
  uint32_t tmp, result;
  for (i = 0; i < ITERATION; i++) {
    uint32_t sc_status = 1;
    while(sc_status != 0) {
        LR_OP(tmp, amo_lrsc[0], w);
        result = tmp + 1;
        SC_OP(sc_status, amo_lrsc[0], result, w);
    }
  }

  // 5. Final sync
  lrsc_add(&amo_cnt[0], 1);
  while(amo_cnt[0] != 2 * core_num);

  return 0;
}