#!/bin/bash
## Run all the unit tests in sw/c/unit_tests

resultfile="verification/unittest_result.log"

widths="256"

function usage() {
    echo "Usage: $0 [options]"
    echo "Run RN-F corner tests"
    echo "Options:"
    echo "  -d                  Give RN-F DAT-channel data widths to be tested for example like \"128 256\". Default is 256"
    echo "                          - Supported widths: 128, 256, 512"
    echo "  -a                  Run corner tests with all DAT-channel data width options."
    echo "  -h                  This helpful help text."
}

OPTIND=1
while getopts "d:ah" OPTION
do
    case $OPTION in
        d)
            widths=$2
            ;;
        a)
            widths="128 256 512"
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




echo > $resultfile


if [[ ! -r "$resultfile" ]]; then
  echo "Error: '$resultfile' not found or not readable" >&2
  exit 1
fi





echo "######################################" > cornertest.log
echo "######################################" >> cornertest.log
echo "Begin Corner Tests" >> cornertest.log
echo "Begin Corner Tests"
echo "######################################" >> cornertest.log
echo "######################################" >> cornertest.log
echo "" >> cornertest.log
echo "" >> cornertest.log



for dw in $widths 
do


  sed -i "s/  constant CHIE_DATA_WIDTH_PARAM          : integer := .*/  constant CHIE_DATA_WIDTH_PARAM          : integer := $dw;/" ${PWD}/cache/include/cache_subsystem_pkg.vhdl

  echo ""
  echo "---- $dw data width ----"
  echo ""

  ##############################
  ## dirtycleandata.c
  echo "" >> cornertest.log
  echo "" >> cornertest.log
  echo "################## dirtycleandata.c ####################" >> cornertest.log
  echo "#### dirtycleandata.c ####"
  ./compile_rnf.sh -t dirtycleandata -c
  ./compile_prog.sh -i dirtycleandata -c &>> cornertest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim_debug.do; run 10000ns; exit;" >> cornertest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  dirtycleandata.c: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  dirtycleandata.c: SUCCEEDED"
    else
      echo "  dirtycleandata.c: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## mixeddataresponse.c
  echo "" >> cornertest.log
  echo "" >> cornertest.log
  echo "################## mixeddataresponse.c ####################" >> cornertest.log
  echo "#### mixeddataresponse.c ####"
  ./compile_rnf.sh -t mixeddataresponse -c
  ./compile_prog.sh -i mixeddataresponse -c &>> cornertest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim_debug.do; run 10000ns; exit;" >> cornertest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  mixeddataresponse.c: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  mixeddataresponse.c: SUCCEEDED"
    else
      echo "  mixeddataresponse.c: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## reversedataresponse.c
  echo "" >> cornertest.log
  echo "" >> cornertest.log
  echo "################## reversedataresponse.c ####################" >> cornertest.log
  echo "#### reversedataresponse.c ####"
  ./compile_rnf.sh -t reversedataresponse -c
  ./compile_prog.sh -i reversedataresponse -c &>> cornertest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim_debug.do; run 10000ns; exit;" >> cornertest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  reversedataresponse.c: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  reversedataresponse.c: SUCCEEDED"
    else
      echo "  reversedataresponse.c: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################
  ## coherencystress.c
  echo "" >> cornertest.log
  echo "" >> cornertest.log
  echo "################## coherencystress.c ####################" >> cornertest.log
  echo "#### coherencystress.c ####"
  ./compile_rnf.sh -t coherencystress -c -d
  ./compile_prog.sh -i coherencystress -c -d &>> cornertest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim_debug.do; run 100000ns; exit;" >> cornertest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  coherencystress.c: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  coherencystress.c: SUCCEEDED"
    else
      echo "  coherencystress.c: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

done

