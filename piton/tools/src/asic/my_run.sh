#!/usr/bin/env bash
SCRPT_FULL_PATH=$(realpath "${BASH_SOURCE[0]}")
SCRPT_DIR_PATH=$(dirname "$SCRPT_FULL_PATH")

ml load synopsys/24-25
ml load  siemens/23-24
ml load riscv-gnu-toolchain/0.7.1



asic_synth -ariane -x_tiles=1 -y_tiles=1 -sys=hpc