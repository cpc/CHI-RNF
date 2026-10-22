// See LICENSE for license details.

//**************************************************************************
// Multi-threaded Matrix Multiply benchmark
//--------------------------------------------------------------------------
// TA     : Christopher Celio
// Student:
//
//
// This benchmark multiplies two 2-D arrays together and writes the results to
// a third vector. The input data (and reference data) should be generated
// using the matmul_gendata.pl perl script and dumped to a file named
// dataset.h.


// print out arrays, etc.
//#define DEBUG

//--------------------------------------------------------------------------
// Includes

// #include <string.h>
//#include <stdlib.h>
// #include <stdio.h>


//--------------------------------------------------------------------------
// Input/Reference Data

#include "dataset.h"


//--------------------------------------------------------------------------
// Basic Utilities and Multi-thread Support

#include "util.h"


//--------------------------------------------------------------------------
// matmul function

 extern void __attribute__((noinline)) matmul(const int coreid, const int ncores, const int lda,  const data_t A[], const data_t B[], data_t C[] );


//--------------------------------------------------------------------------
// Main
//
// all threads start executing thread_entry(). Use their "coreid" to
// differentiate between threads (each thread is running on a separate core).

#define barrier_base 0x0000000080040000
#define mutex_base 0x0000000080050000

int thread_entry(int cid, int nc)
{
   volatile uint32_t *barrier = (uint32_t *) barrier_base;
   volatile uint32_t *mutex = (uint32_t *) mutex_base;
   // Use volatile to ensure memory is re-read during verification
   static volatile data_t results_data[ARRAY_SIZE];

   uint32_t tmp, status;

   *barrier = 0;
   *mutex = 0;

   // 1. Perform local work
   matmul(cid, nc, DIM_SIZE, input1_data, input2_data, results_data);

   /* --- LR/SC Barrier Increment --- */
   // Atomic Add: *barrier = *barrier + 1
   __asm__ __volatile__ (
       "1: lr.w.aq %0, (%2)      \n" // Load reserved with acquire
       "   addi    %0, %0, 1     \n" // Increment
       "   sc.w.rl %1, %0, (%2)  \n" // Store conditional with release
       "   bnez    %1, 1b        \n" // Retry if failed
       : "=&r" (tmp), "=&r" (status)
       : "r" (barrier)
       : "memory"
   );

   // Wait for all cores to arrive
   while (*barrier != nc){};

   /* --- Mutex Acquisition (Spin-wait) --- */
   // This serializes the verification phase
   while (*mutex != cid){};

   // 2. Critical Section: Verify the work
   int res = verifyDouble(ARRAY_SIZE, results_data, verify_data);

   /* --- LR/SC Mutex Release --- */
   // Atomic Add: *mutex = *mutex + 1
   // This passes the "ticket" to the next core (cid + 1)
   __asm__ __volatile__ (
       "1: lr.w.aq %0, (%2)      \n"
       "   addi    %0, %0, 1     \n"
       "   sc.w.rl %1, %0, (%2)  \n"
       "   bnez    %1, 1b        \n"
       : "=&r" (tmp), "=&r" (status)
       : "r" (mutex)
       : "memory"
   );

   return res;
}