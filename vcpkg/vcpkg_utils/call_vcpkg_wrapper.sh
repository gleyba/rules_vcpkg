#!/usr/bin/env bash

set -eu

export HOME=/tmp/home
export PATH="${PWD}/${CMAKE_BIN}:/usr/bin:/bin"

prepare_install_dir_bin="${PWD}/${PREPARE_INSTALL_DIR_BIN}"
prepare_install_dir_args=()

vcpkg_bin="${PWD}/${VCPKG_BIN}"
vcpkg_args=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --)
        prepare_install_dir_args=("${vcpkg_args[@]}")
        vcpkg_args=()
        shift
        ;;
    *)
        vcpkg_args+=("$1")
        shift
        ;;
  esac
done

"${prepare_install_dir_bin}" "${prepare_install_dir_args[@]}"
"${vcpkg_bin}" "${vcpkg_args[@]}"
