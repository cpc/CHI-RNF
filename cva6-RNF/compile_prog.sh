#!/bin/bash
## Compile program for RNF-CVA6

rnfcount=1
program=""
type=c
#langstandard=gnu99
langstandard=gnu11
runtime_enabled=0
rvb_build=rnf_1core
test=0
unit=0
corner=0


function usage() {
    echo "Usage: $0 -i -program- [options]"
    echo "Compiles and prepares the program for RTL simulation."
    echo ""
    echo "Options:"
    echo "  -i -program-    Give the name of the program to be compiled"
    echo "  -d              Compile the program for 2core system"
    echo "  -p              Compile C++ code. No effect with runtime"
    echo "  -u              Compile unit test under sw/c/unit_tests"
    echo "  -c              Compile corner test under sw/c/corners"
    echo "  -r              Compile the program with the riscvbarelib runtime library. Needs to be set up before (build&sw). "
    echo "                      - DOESN'T WORK ATM. Needs interrupts to be enabled with the CVA6"
    echo "  -h              This helpful help text."
    echo "Example: "
    echo "      ./compile_prog -i hello_world -d"
    echo ""
    echo "The setup_piton.sh should only be sourced when compiling just bare-metal program."
    echo "The program should be under ${RISCV_ROOT}/sw/c."
    echo ""
    echo "If using the runtime lib, source also the sw/riscvbarelib/setup.sh."
    echo "The program using runtime lib should be under ${RISCV_ROOT}/sw/riscvbarelib/-build_dir-/-program_dir-, and there should be also a makefile for it."
    echo "The directory, where the program and its makefile are located, should be named after the program."
    echo "    Check the sw/riscvbarelib/rnf_1core/hello directory and mimic from there."
}

OPTIND=1
while getopts "i:dhprtuc" OPTION
do
    case $OPTION in
        i)
            program=$2
            ;;
        d)
            rnfcount=2
            rvb_build=rnf_2core
            ;;
        p)
            type=cc
            langstandard=c++20
            ;;
        r)
            runtime_enabled=1
            ;;
        t)
            test=1
            ;;
        u)
            unit=1
            ;;
        c)
            corner=1
            ;;
        h)
            usage
            exit 0
            ;;
        ?)
            echo "Unknown option -$OPTARG"
            usage
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

if [ "$program" = "" ]; then
    echo "The program name was not given."
    usage
    exit 1
fi


rm sw/${program}.elf
rm sw/prog.hex
rm prog.img




echo > prog_compilation.txt

# Compile the program according to flags
if [ $runtime_enabled = 1 ]; then

    export RVB_BUILD=${PWD}/sw/riscvbarelib/${rvb_build}
    cd $RVB_BUILD/${program}
    make clean || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh; source -RVB_HOME-/setup.sh"; cd $RNF_ROOT; exit 1; }
    make all || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh; source -RVB_HOME-/setup.sh"; cd $RNF_ROOT; exit 1; }
    cp build/${program}.elf ${RNF_ROOT}/sw/${program}.elf || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh; source -RVB_HOME-/setup.sh"; cd $RNF_ROOT; exit 1; }
    cd $RNF_ROOT

elif [ $program = "matmul" ]; then

        riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/mt-matmul/${program}.c ${RNF_ROOT}/sw/c/mt-matmul/mt-matmul.c ${RNF_ROOT}/sw/c/mthread_main.c ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostdlib -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }

elif [ $program = "vvadd" ]; then

        riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/mt-vvadd/${program}.c ${RNF_ROOT}/sw/c/mt-vvadd/mt-vvadd.c ${RNF_ROOT}/sw/c/mthread_main.c ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }

elif [ $test = 1 ]; then

    riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/tests/${program}.${type} ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostdlib -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }

elif [ $unit = 1 ]; then

    riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/unit_tests/${program}.${type} ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostdlib -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }

elif [ $corner = 1 ]; then

    riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/corners/${program}.${type} ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostdlib -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }

else
    # Compile the program to .elf
    riscv64-unknown-elf-gcc  \
            -I ${RNF_ROOT}/sw/include \
            -march=rv64imafdc  \
            -mabi=lp64d  \
            -DPREALLOCATE=1  \
            -mcmodel=medany  \
            -static  \
            -std=${langstandard}  \
            -O2  \
            -fno-common  \
            -fno-builtin-printf  \
            -DPITON_NUMTILES=${rnfcount} \
            -o sw/${program}.elf ${RNF_ROOT}/sw/c/${program}.${type} ${RNF_ROOT}/sw/include/syscalls.c ${RNF_ROOT}/sw/include/crt.S \
            -static -nostdlib -nostartfiles -lm -lgcc \
            -T ${RNF_ROOT}/sw/include/link.ld >> prog_compilation.txt 2>&1 || { echo "Compilation finished with ERRORS! Remember to do: source setup_piton.sh"; exit 1; }
fi

# Convert the .elf to .hex
riscv64-unknown-elf-elf2hex --bit-width 32 --input sw/${program}.elf --output sw/prog.hex >> prog_compilation.txt || exit 1

# Convert the .hex to .img (the program in binary text file)
# oa-hex2bin -w 32 -o prog.img sw/prog.hex >> prog_compilation.txt || exit 1
xxd -r -p sw/prog.hex sw/prog.img >> prog_compilation.txt || exit 1

# Generate also the program in assembly
riscv64-unknown-elf-objdump --disassemble-all sw/${program}.elf > prog.disasm


