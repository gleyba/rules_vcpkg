#!/usr/bin/env bash

set -eu

export HOME=/tmp/home
export PATH="${PWD}/__bin_dir__:${PWD}/__cur_bin_dir__" # ":/usr/bin:/bin"

export VCPKG_EXEC_ROOT="${PWD}"
# export CC="__cxx_compiler__"
# export CXX="__cxx_compiler__"

export VCPKG_OVERLAY_TRIPLETS="${VCPKG_EXEC_ROOT}/__overlay_tripplets__"
export VCPKG_ROOT="${VCPKG_EXEC_ROOT}/__vcpkg_root__"

vcpkg_bin="${PWD}/__vcpkg_bin__"
prepare_install_dir_bin="${PWD}/__prepare_install_dir_bin__"

: "${VCPKG_DEBUG:=0}"

if [[ "${VCPKG_DEBUG}" == 1 ]]; then 
  buildtrees_tmp="/tmp/vcpkg.builtree.__package_name__"
  # rm -rf "${buildtrees_tmp}"
  mkdir -p "${buildtrees_tmp}"
  echo "🚨 RULES_VCPKG 🚨: using buildtree in ${buildtrees_tmp}"
else
  buildtrees_tmp="$(mktemp -t -d vcpkg.builtree.__package_name__.XXXXXX)"
  trap 'rm -rf "${buildtrees_tmp}"' EXIT 
fi

install_root_tmp="${buildtrees_tmp}/install_root"
ln -sf "${VCPKG_EXEC_ROOT}/__install_root__" "${install_root_tmp}"

"${prepare_install_dir_bin}" \
  __install_dir_path__ \
  __packages_list_file__ \
  __buildtrees_root__ \
  "${buildtrees_tmp}"

"${vcpkg_bin}" \
  build \
  __build_target_name__ \
  --vcpkg-root=__vcpkg_root__ \
  --overlay-triplets=__overlay_tripplets__ \
  --x-buildtrees-root="${buildtrees_tmp}" \
  --downloads-root=__downloads_root__ \
  --x-install-root="${install_root_tmp}" \
  --x-packages-root=__packages_root__
