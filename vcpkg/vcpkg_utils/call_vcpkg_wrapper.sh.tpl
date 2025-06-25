#!/usr/bin/env bash

set -eu

export HOME=/tmp/home
export PATH="${PWD}/__bin_dir__" # ":/usr/bin:/bin"

export VCPKG_EXEC_ROOT="${PWD}"
export CC="__cxx_compiler__"
export CXX="__cxx_compiler__"
export VCPKG_OVERLAY_TRIPLETS="${VCPKG_EXEC_ROOT}/__overlay_tripplets__"

vcpkg_bin="${PWD}/__vcpkg_bin__"
prepare_install_dir_bin="${PWD}/__prepare_install_dir_bin__"

if [ -z "${VCPKG_DEBUG}" ]; then 
  buildtrees_tmp="$(mktemp -t -d vcpkg.builtree.__package_name__.XXXXXX)"
  trap 'rm -rf "${buildtrees_tmp}"' EXIT 
else
  buildtrees_tmp="/tmp/vcpkg.builtree.__package_name__"
  rm -rf "${buildtrees_tmp}"
  mkdir -p "${buildtrees_tmp}"
fi

"${prepare_install_dir_bin}" \
  __install_dir_path__ \
  __packages_list_file__ \
  __buildtrees_root__ \
  "${buildtrees_tmp}"

"${vcpkg_bin}" \
  build \
  __package_name__ \
  --vcpkg-root=__vcpkg_root__ \
  --overlay-triplets=__overlay_tripplets__ \
  --x-buildtrees-root="${buildtrees_tmp}" \
  --downloads-root=__downloads_root__ \
  --x-install-root=__install_root__ \
  --x-packages-root=__packages_root__
