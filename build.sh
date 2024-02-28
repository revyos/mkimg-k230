#!/usr/bin/env bash

set -eu

# ci redefined
BUILD_DIR=${BUILD_DIR:-build}
OUTPUT_DIR=${OUTPUT_DIR:-output}
VENV_DIR=${VENV_DIR:-venv}
ABI=${ABI:-rv64}
BOARD=${BOARD:-canmv}
ARCH=${ARCH:-riscv}
CROSS_COMPILE=${CROSS_COMPILE:-riscv64-unknown-linux-gnu-}

LINUX_BUILD=${LINUX_BUILD:-build}
OPENSBI_BUILD=${OPENSBI_BUILD:-build}
UBOOT_BUILD=${UBOOT_BUILD:-build-uboot}

mkdir -p ${BUILD_DIR} ${OUTPUT_DIR}

OUTPUT_DIR=$(readlink -f ${OUTPUT_DIR})
SCRIPT_DIR=$(readlink -f $(dirname $0))

function build_linux() {
  pushd linux
  {
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} k230_evb_linux_enable_vector_defconfig
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} -j$(nproc) dtbs
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} -j$(nproc)

    cp -v ${LINUX_BUILD}/vmlinux ${OUTPUT_DIR}/vmlinux_${ABI}
    cp -v ${LINUX_BUILD}/arch/riscv/boot/Image ${OUTPUT_DIR}/Image_${ABI}
    cp -v Documentation/admin-guide/kdump/gdbmacros.txt ${OUTPUT_DIR}/gdbmacros_${ABI}.txt
    cp -v ${LINUX_BUILD}/arch/riscv/boot/dts/canaan/k230_evb.dtb ${OUTPUT_DIR}/k230_evb_${ABI}.dtb
    cp -v ${LINUX_BUILD}/arch/riscv/boot/dts/canaan/k230_canmv.dtb ${OUTPUT_DIR}/k230_canmv_${ABI}.dtb
  }
  popd
}

function build_opensbi() {
  pushd opensbi
  {
    make \
      ARCH=${ARCH} \
      CROSS_COMPILE=${CROSS_COMPILE} \
      O=${OPENSBI_BUILD} \
      PLATFORM=generic \
      FW_PAYLOAD=y \
      FW_FDT_PATH=${OUTPUT_DIR}/k230_${BOARD}_${ABI}.dtb \
      FW_PAYLOAD_PATH=${OUTPUT_DIR}/Image_${ABI} \
      FW_TEXT_START=0x0 \
      -j $(nproc)
    cp -v ${OPENSBI_BUILD}/platform/generic/firmware/fw_payload.bin ${OUTPUT_DIR}/k230_${BOARD}_${ABI}.bin
  }
  popd
}

function build_uboot() {
  python3 -m venv ${VENV_DIR}
  source ${VENV_DIR}/bin/activate
  pip install gmssl
  pushd uboot
  {
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${UBOOT_BUILD} k230_${BOARD}_defconfig
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${UBOOT_BUILD} -j$(nproc)
    cp -av ${UBOOT_BUILD}/u-boot-spl-k230.bin ${OUTPUT_DIR}/u-boot-spl-k230_${BOARD}.bin
    cp -av ${UBOOT_BUILD}/fn_u-boot.img ${OUTPUT_DIR}/fn_u-boot_${BOARD}.img
  }
  popd
  deactivate
}

function cleanup_build() {
  pushd ${SCRIPT_DIR}
  {
    rm -rvf ${OUTPUT_DIR} ${BUILD_DIR}
    rm -rvf uboot/${UBOOT_BUILD} opensbi/${OPENSBI_BUILD} linux/${LINUX_BUILD}
    rm -rvf ${VENV_DIR}
  }
  popd
}

function usage() {
  echo "Usage: $0 build/clean"
}

function fault() {
  usage
  exit 1
}

function main() {

  if [[ $# < 1 ]]; then
    fault
  fi

  if [ "$1" = "build" ]; then
    if [ "$2" = "linux" ]; then
      build_linux
    elif [ "$2" = "opensbi" ]; then
      build_opensbi
    elif [ "$2" = "uboot" ]; then
      build_uboot
    elif [ "$2" = "all" ]; then
      build_linux
      build_opensbi
      build_uboot
    else
      fault
    fi
  elif [ "$1" = "clean" ]; then
    cleanup_build
  else
    fault
  fi
}

main $@
