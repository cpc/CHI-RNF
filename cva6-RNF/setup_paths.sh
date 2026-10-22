#!/bin/bash
# Set RNF paths

export RNF_ROOT=`pwd`
export PROJ_ROOT=`pwd`/..

# Path to RISCV compiler
#export RISCV=${HOME}/Desktop/Work/DARE-projekti/opensource/op_cva6/riscv_tc/riscv64-unknown-elf-gcc-10.1.0-2020.08.2-x86_64-linux-ubuntu14
export RISCV=path/to/compiler/riscv64-unknown-elf-gcc-10.1.0-2020.08.2-x86_64-linux-ubuntu14

export PATH=$RISCV/bin:$PATH
export LIBRARY_PATH=$RISCV/lib
export LD_LIBRARY_PATH=$RISCV/lib
export C_INCLUDE_PATH=$RISCV/include
export CPLUS_INCLUDE_PATH=$RISCV/include