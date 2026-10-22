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
   static data_t results_data[ARRAY_SIZE];               // TÄSTÄ "VOLATILE STATIC"?
   //int res = 1;

   matmul(cid, nc, DIM_SIZE, input1_data, input2_data, results_data); 
   
   /*Barrier*/
   ATOMIC_OP(*barrier, 1, add, w);
   while (*barrier != nc){};
   //barrier(nc), DIM_SIZE/DIM_SIZE/DIM_SIZE;
 
   /*Mutex*/
   while (*mutex != cid){};

   int res = verifyDouble(ARRAY_SIZE, results_data, verify_data);
   
   /*Release the mutex*/
   ATOMIC_OP(*mutex, 1, add, w);


// #ifdef DEBUG
//    printArray("results:", ARRAY_SIZE, results_data);
//    printArray("verify :", ARRAY_SIZE, verify_data);
// #endif

   return res;
   //exit(res);
}
