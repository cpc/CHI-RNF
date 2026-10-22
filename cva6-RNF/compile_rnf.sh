#!/bin/bash
## Compile RNF-CVA6

doublecore=no
rnf_count=1
unit=0
corner=0
test="none"

function usage() {
    echo "Usage: $0 [options]"
    echo "Prepares RN-F design for RTL simulation."
    echo "Options:"
    echo "  -t -test-           If compiling for unit/corner test setup, give also the test name."
    echo "  -u                  Compile for unit testing."
    echo "  -c                  Compile for corner testing."
    echo "  -d                  Compile with 2-RNF, multicore system."
    echo "  -h                  This helpful help text."
}

OPTIND=1
while getopts "t:dhuc" OPTION
do
    case $OPTION in
        t)
            test=$2
            ;;
        d)
            doublecore=yes
            ;;
        h)
            usage
            exit 0
            ;;
        u)
            unit=1
            ;;
        c)
            corner=1
            ;;
        ?)  
            echo "Unknown option -$OPTARG"
            usage
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

echo "Compile riscv-rnf" > compile_log.txt
echo "" >> compile_log.txt
echo "" >> compile_log.txt

rm -rf work     >> compile_log.txt
vlib work       >> compile_log.txt
vmap            >> compile_log.txt

echo "" >> compile_log.txt
echo "" >> compile_log.txt



# Setup testbench according to compiled test
if [ $unit -eq 1 -a $test = "readunique" ]; then
    sed -i "s/  variable do_readunique_test : std_logic .*/  variable do_readunique_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "readshared" ]; then
    sed -i "s/  variable do_readshared_test : std_logic .*/  variable do_readshared_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "writebackptl" -o $test = "writeback" ]; then
    sed -i "s/  variable do_writebackptl_test : std_logic .*/  variable do_writebackptl_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "writenosnp" ]; then
    sed -i "s/  variable do_writenosnp_test : std_logic .*/  variable do_writenosnp_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "amoadd_swap" ]; then
    sed -i "s/  variable do_amoadd_swap_test : std_logic .*/  variable do_amoadd_swap_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "atomicload" ]; then
    sed -i "s/  variable do_atomicload_test : std_logic .*/  variable do_atomicload_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpunique" ]; then
    sed -i "s/  variable do_unique_snoop : std_logic .*/  variable do_unique_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpunique_empty" ]; then
    sed -i "s/  variable do_unique_snoop : std_logic .*/  variable do_unique_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
    sed -i "s/  variable expect_empty_snpresp : std_logic .*/  variable expect_empty_snpresp : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpshared" ]; then
    sed -i "s/  variable do_shared_snoop : std_logic .*/  variable do_shared_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpclean" ]; then
    sed -i "s/  variable do_clean_snoop : std_logic .*/  variable do_clean_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "rettosrc_snp" ]; then
    sed -i "s/  variable do_rettosrc_snoop : std_logic .*/  variable do_rettosrc_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpcleaninvalid" ]; then
    sed -i "s/  variable do_cleaninvalid_snoop : std_logic .*/  variable do_cleaninvalid_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "snpmakeinvalid" ]; then
    sed -i "s/  variable do_makeinvalid_snoop : std_logic .*/  variable do_makeinvalid_snoop : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
    echo "Compile snpunique program with the snpmakeinvalid-test"
elif [ $unit -eq 1 -a $test = "writecleanfull" ]; then
    sed -i "s/  variable send_unique_dirty_cline : std_logic .*/  variable send_unique_dirty_cline : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $unit -eq 1 -a $test = "separate_response" ]; then
    sed -i "s/  variable do_separate_resp : std_logic .*/  variable do_separate_resp : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
    sed -i "s/  variable do_readunique_test : std_logic .*/  variable do_readunique_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
    echo "Compile readunique.c program with separate_response-test"
fi


# Setup testbench according to compiled test
if [ $corner -eq 1 -a $test = "dirtycleandata" ]; then
    sed -i "s/  variable send_unique_dirty_cline : std_logic .*/  variable send_unique_dirty_cline : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
    sed -i "s/  variable do_mixeddata_test : std_logic .*/  variable do_mixeddata_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $corner -eq 1 -a $test = "mixeddataresponse" ]; then
    sed -i "s/  variable do_mixeddata_test : std_logic .*/  variable do_mixeddata_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $corner -eq 1 -a $test = "reversedataresponse" ]; then
    sed -i "s/  variable do_reverseresponse_test : std_logic .*/  variable do_reverseresponse_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
elif [ $corner -eq 1 -a $test = "coherencystress" ]; then
    sed -i "s/  variable do_coherencystress_test : std_logic .*/  variable do_coherencystress_test : std_logic := '1';/" ${PWD}/tb/riscv_rnf_tb.vhdl
fi

sed -i "s/  variable unit_test : std_logic .*/  variable unit_test : std_logic := '$unit';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable corner_test : std_logic .*/  variable corner_test : std_logic := '$corner';/" ${PWD}/tb/riscv_rnf_tb.vhdl


if [ $unit -eq 1 ]; then
    echo "Unit test setup"
elif [ $corner -eq 1 ]; then
    echo "Corner test setup"
fi


# 
if [ $doublecore = "yes" ]; then
    echo "Compiling design with 2 RNFs"
    echo "Compiling design with 2 RNFs" >> compile_log.txt
    echo "" >> compile_log.txt
    vlog -mfcu -suppress 2583 -f cache/rnf_flist >> compile_log.txt || { echo "Compilation finished with ERRORS! Check compile_log"; exit 1; }
    rnf_count=2
fi
if [ $doublecore = "no" ]; then
    echo "Compiling design with 1 RNF"
    echo "Compiling design with 1 RNF" >> compile_log.txt
    echo "" >> compile_log.txt
    vlog -mfcu -suppress 2583 -f cache/rnf_flist >> compile_log.txt || { echo "Compilation finished with ERRORS! Check compile_log"; exit 1; }
    rnf_count=1
fi

echo "" >> compile_log.txt
echo "" >> compile_log.txt

# Set the RNF count to the testbench
sed -i "s/  constant rnf_count : integer .*/  constant rnf_count : integer := $rnf_count;/" ${PWD}/tb/riscv_rnf_tb.vhdl

vcom cache/include/cache_subsystem_pkg.vhdl     >> compile_log.txt || { echo "Compilation finished with ERRORS! Check compile_log"; exit 1; }
vcom tb/rnf_wrapper.vhdl                        >> compile_log.txt || { echo "Compilation finished with ERRORS! Check compile_log"; exit 1; }
vcom tb/riscv_rnf_tb.vhdl                       >> compile_log.txt || { echo "Compilation finished with ERRORS! Check compile_log"; exit 1; }






#  write initial values back after compiling the system
sed -i "s/  variable do_readunique_test : std_logic .*/  variable do_readunique_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_readshared_test : std_logic .*/  variable do_readshared_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_writebackptl_test : std_logic .*/  variable do_writebackptl_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_writenosnp_test : std_logic .*/  variable do_writenosnp_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_amoadd_swap_test : std_logic .*/  variable do_amoadd_swap_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_atomicload_test : std_logic .*/  variable do_atomicload_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl

sed -i "s/  variable corner_test : std_logic .*/  variable corner_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable unit_test : std_logic .*/  variable unit_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_unique_snoop : std_logic .*/  variable do_unique_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable expect_empty_snpresp : std_logic .*/  variable expect_empty_snpresp : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_shared_snoop : std_logic .*/  variable do_shared_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_clean_snoop : std_logic .*/  variable do_clean_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_cleaninvalid_snoop : std_logic .*/  variable do_cleaninvalid_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_makeinvalid_snoop : std_logic .*/  variable do_makeinvalid_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable send_unique_dirty_cline : std_logic .*/  variable send_unique_dirty_cline : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_mixeddata_test : std_logic .*/  variable do_mixeddata_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_reverseresponse_test : std_logic .*/  variable do_reverseresponse_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_coherencystress_test : std_logic .*/  variable do_coherencystress_test : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_separate_resp : std_logic .*/  variable do_separate_resp : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl
sed -i "s/  variable do_rettosrc_snoop : std_logic .*/  variable do_rettosrc_snoop : std_logic := '0';/" ${PWD}/tb/riscv_rnf_tb.vhdl


