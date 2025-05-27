#!/bin/bash

# Author: Oscar Lostes Cazorla <oscar.lostes@bsc.es>, BSC
# Date: 26.11.2018
# Description: This script builds the RISCV toolchain, benchmarks, assembly tests
# the RISCV FESVR and the RISCV Torture framework for OpenPiton+Sargantana configurations.
# Please source the sargantana_setup.sh first.
#
#
# Make sure you have the following packages installed:
#
# sudo apt install \
#          gcc-7 \
#          g++-7 \
#          gperf \
#          autoconf \
#          automake \
#          autotools-dev \
#          libmpc-dev \
#          libmpfr-dev \
#          libgmp-dev \
#          gawk \
#          build-essential \
#          bison \
#          flex \
#          texinfo \
#          python-pexpect \
#          libusb-1.0-0-dev \
#          default-jdk \
#          zlib1g-dev \
#          valgrind \
#          csh

CI_TOKEN=$1

echo
echo "----------------------------------------------------------------------"
echo "building RISCV toolchain and tests (if not existing)"
echo "----------------------------------------------------------------------"
echo

if [[ "${RISCV}" == "" ]]
then
    echo "Please source sargantana_setup.sh first, while being in the root folder."
else

  [ -d ${SARG_ROOT} ] || git submodule update --init --recursive piton/design/chip/tile/sargantana

  # parallel compilation
  export NUM_JOBS=6

  cd ${SARG_ROOT}

  # build the RISCV tests if necessary
  VERSION="v1.2.1"
  mkdir -p ${SARG_ROOT}/tmp
  cd tmp

  TESTS_URL="https://gitlab.bsc.es/hwdesign/rtl/uncore/riscv-tests.git"

  if [[ $# -eq 1 ]]; then
    echo "Using GitLab CI Token"
    TESTS_URL=$(echo $TESTS_URL | sed "s/https:\/\//https:\/\/gitlab-ci-token:$CI_TOKEN@/")
  fi

  [ -d riscv-tests ] || git clone $TESTS_URL
  cd riscv-tests
  git checkout $VERSION
  git submodule update --init --recursive
  autoconf
  mkdir -p build

  # link in adapted syscalls.c such that the benchmarks can be used in the OpenPiton TB
  #cd benchmarks/common/
  #rm syscalls.c util.h
  #ln -s ${PITON_ROOT}/piton/verif/diag/assembly/include/riscv/sargantana/syscalls.c
  #ln -s ${PITON_ROOT}/piton/verif/diag/assembly/include/riscv/sargantana/util.h
  #cd -

  cd build
  tmp_dest=$SARG_ROOT/tmp
  if [ -w /tmp ]
  then
    tmp_dest=/tmp
  fi
  ../configure --prefix=$tmp_dest/riscv-tests/build

  make clean
  make isa        -j${NUM_JOBS} > /dev/null
  NUM_TILES=1 make benchmarks -j${NUM_JOBS} > /dev/null
  make install
  cd ${PITON_ROOT}

  cd $SARG_ROOT
  make libdisasm

  echo
  echo "----------------------------------------------------------------------"
  echo "build complete"
  echo "----------------------------------------------------------------------"
  echo

fi
