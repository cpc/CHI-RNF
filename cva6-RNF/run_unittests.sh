#!/bin/bash
## Run all the unit tests in sw/c/unit_tests

resultfile="verification/unittest_result.log"
widths="256"

function usage() {
    echo "Usage: $0 [options]"
    echo "Run RN-F unit tests"
    echo "Options:"
    echo "  -d                  Give RN-F DAT-channel data widths to be tested for example like \"128 256\". Default is 256"
    echo "                          - Supported widths: 128, 256, 512"
    echo "  -a                  Run unit tests with all DAT-channel data width options."
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



  echo "######################################" > unittest.log
  echo "######################################" >> unittest.log
  echo "Begin Unit Tests" >> unittest.log
  echo "Begin Unit Tests"
  echo "######################################" >> unittest.log
  echo "######################################" >> unittest.log
  echo "" >> unittest.log
  echo "" >> unittest.log


for dw in $widths 
do

  sed -i "s/  constant CHIE_DATA_WIDTH_PARAM          : integer := .*/  constant CHIE_DATA_WIDTH_PARAM          : integer := $dw;/" ${PWD}/cache/include/cache_subsystem_pkg.vhdl

  echo ""
  echo "---- $dw data width ----"
  echo ""

  ##############################
  ## amoadd_swap.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## amoadd_swap ####################" >> unittest.log
  echo "#### amoadd_swap ####"
  ./compile_rnf.sh -t amoadd_swap -u
  ./compile_prog.sh -i amoadd_swap -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  amoadd_swap: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  amoadd_swap: SUCCEEDED"
    else
      echo "  amoadd_swap: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## atomicload.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## atomicload ####################" >> unittest.log
  echo "#### atomicload ####"
  ./compile_rnf.sh -t atomicload -u
  ./compile_prog.sh -i atomicload -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  atomicload: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  atomicload: SUCCEEDED"
    else
      echo "  atomicload: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## readshared.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## readshared ####################" >> unittest.log
  echo "#### readshared ####"
  ./compile_rnf.sh -t readshared -u
  ./compile_prog.sh -i readshared -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  readshared: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  readshared: SUCCEEDED"
    else
      echo "  readshared: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## readunique.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## readunique ####################" >> unittest.log
  echo "#### readunique ####"
  ./compile_rnf.sh -t readunique -u
  ./compile_prog.sh -i readunique -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  readunique: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  readunique: SUCCEEDED"
    else
      echo "  readunique: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################
  ## cleanunique.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## cleanunique ####################" >> unittest.log
  echo "#### cleanunique ####"
  ./compile_rnf.sh -t cleanunique -u
  ./compile_prog.sh -i cleanunique -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  cleanunique: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  cleanunique: SUCCEEDED"
    else
      echo "  cleanunique: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################
  ## snpunique.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpunique ####################" >> unittest.log
  echo "#### snpunique ####"
  ./compile_rnf.sh -t snpunique -u
  ./compile_prog.sh -i snpunique -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpunique: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpunique: SUCCEEDED"
    else
      echo "  snpunique: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""




  ##############################
  ## snpshared.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpshared ####################" >> unittest.log
  echo "#### snpshared ####"
  ./compile_rnf.sh -t snpshared -u
  ./compile_prog.sh -i snpshared -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpshared: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpshared: SUCCEEDED"
    else
      echo "  snpshared: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################
  ## snpclean.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpclean ####################" >> unittest.log
  echo "#### snpclean ####"
  ./compile_rnf.sh -t snpclean -u
  ./compile_prog.sh -i snpclean -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpclean: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpclean: SUCCEEDED"
    else
      echo "  snpclean: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""


  ##############################
  ## snpcleaninvalid.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpcleaninvalid ####################" >> unittest.log
  echo "#### snpcleaninvalid (snpclean.c) ####"
  ./compile_rnf.sh -t snpcleaninvalid -u
  ./compile_prog.sh -i snpclean -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpcleaninvalid: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpcleaninvalid: SUCCEEDED"
    else
      echo "  snpcleaninvalid: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""


  ##############################
  ## snpmakeinvalid.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpmakeinvalid ####################" >> unittest.log
  echo "#### snpmakeinvalid (snpunique.c) ####"
  ./compile_rnf.sh -t snpmakeinvalid -u
  ./compile_prog.sh -i snpunique -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpmakeinvalid: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpmakeinvalid: SUCCEEDED"
    else
      echo "  snpmakeinvalid: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""


  ##############################
  ## snpunique_empty.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## snpunique_empty ####################" >> unittest.log
  echo "#### snpunique_empty ####"
  ./compile_rnf.sh -t snpunique_empty -u
  ./compile_prog.sh -i snpunique_empty -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  snpunique_empty: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  snpunique_empty: SUCCEEDED"
    else
      echo "  snpunique_empty: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""


  ##############################
  ## rettosrc_snp.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## rettosrc_snp ####################" >> unittest.log
  echo "#### rettosrc_snp ####"
  ./compile_rnf.sh -t rettosrc_snp -u
  ./compile_prog.sh -i rettosrc_snp -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  rettosrc_snp: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  rettosrc_snp: SUCCEEDED"
    else
      echo "  rettosrc_snp: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################
  ## writeback.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## writeback ####################" >> unittest.log
  echo "#### writeback ####"
  ./compile_rnf.sh -t writeback -u
  ./compile_prog.sh -i writeback -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  writeback: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  writeback: SUCCEEDED"
    else
      echo "  writeback: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""

  ##############################
  ## writenosnp.c
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## writenosnp ####################" >> unittest.log
  echo "#### writenosnp ####"
  ./compile_rnf.sh -t writenosnp -u
  ./compile_prog.sh -i writenosnp -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  writenosnp: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  writenosnp: SUCCEEDED"
    else
      echo "  writenosnp: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi


  echo > $resultfile
  echo ""


  ##############################
  ## separate_response (readunique.c)
  echo "" >> unittest.log
  echo "" >> unittest.log
  echo "################## separate_response ####################" >> unittest.log
  echo "#### separate_response (readunique.c) ####"
  ./compile_rnf.sh -t separate_response -u
  ./compile_prog.sh -i readunique -u &>> unittest.log
  vsim -c -t 10ps -voptargs="+acc" riscv_rnf_tb -do "do RNF_sim.do; run 10000ns; exit;" >> unittest.log

  # Read the first line (preserve leading/trailing spaces, backslashes)
  IFS= read -r firstline < "$resultfile" || firstline=""
  # Optional: trim whitespace
  trimmed=${firstline#"${firstline%%[![:space:]]*}"}      # ltrim
  trimmed=${trimmed%"${trimmed##*[![:space:]]}"}          # rtrim
  # Check the value
  if [[ -z "$trimmed" ]]; then
    echo "First line is empty/whitespace"
    echo "  separate_response: FAILED"
  elif [[ "$trimmed" =~ ^[0-9]+$ ]]; then
    if (( trimmed = 1 )); then
      echo "  separate_response: SUCCEEDED"
    else
      echo "  separate_response: FAILED"
    fi
  elif [[ "$trimmed" == ERROR:* ]]; then
    echo "Found error: ${trimmed#ERROR:}"
  else
    echo "First line: '$trimmed'"
  fi

  echo > $resultfile
  echo ""



  ##############################


done # Data-width iteration loop done


