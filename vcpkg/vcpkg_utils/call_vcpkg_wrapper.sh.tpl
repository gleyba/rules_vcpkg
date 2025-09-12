#!/usr/bin/env bash

set -eu pipefail

if [[ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]]; then
  set -x
fi

export HOME=/tmp/home
export PATH="${PWD}/__bin_dir__"
export M4="${PWD}/__bin_dir__/m4"

export VCPKG_EXEC_ROOT="${PWD}"

export VCPKG_OVERLAY_TRIPLETS="${VCPKG_EXEC_ROOT}/__overlay_tripplets__"
export VCPKG_ROOT="${VCPKG_EXEC_ROOT}/__vcpkg_root__"

export CC=__cc_compiler__
export CXX=__cxx_compiler__

export ADDITIONAL_CFLAGS="__cflags__"
export ADDITIONAL_LINKER_FLAGS="__linkerflags__"

vcpkg_bin="${PWD}/__vcpkg_bin__"
prepare_install_dir_bin="${PWD}/__prepare_install_dir_bin__"

: "${VCPKG_DEBUG:=0}"
: "${VCPKG_DEBUG_REUSE_OUTPUTS:=0}"

if [[ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]]; then
  unset VCPKG_MAX_CONCURRENCY
fi

if [[ "${VCPKG_DEBUG}" == 1 ]]; then
  buildtrees_tmp="/tmp/vcpkg/builtrees/__package_name__"
  if [ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 0 ]; then 
    rm -rf "${buildtrees_tmp}"
  fi
  echo "🚨 RULES_VCPKG 🚨: using buildtree in ${buildtrees_tmp}"
else
  buildtrees_tmp="$(mktemp -d -t vcpkg.builtree.__package_name__.XXXXXX)"
  trap 'rm -rf "${buildtrees_tmp}"' EXIT 
fi

packages_dir="${buildtrees_tmp}/packages"

if [ "${VCPKG_DEBUG}" == 1 ] && [ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]; then 
  if [[ -f "$packages_dir/__package_output_basename__/CONTROL" ]]; then
    echo "⚠️ RULES_VCPKG ⚠️: reusing output from: '$packages_dir/__package_output_basename__'"
    cp -r "$packages_dir/__package_output_basename__" "__package_output_dir__"
    exit 0
  else
    rm -rf "${buildtrees_tmp}"
  fi
fi

install_root_tmp="${buildtrees_tmp}/install"
mkdir -p "${install_root_tmp}"

ln -sf "${VCPKG_EXEC_ROOT}/__downloads_root__" "${buildtrees_tmp}/downloads"

rm -rf "${buildtrees_tmp}/install"

"${prepare_install_dir_bin}" \
  "${buildtrees_tmp}" \
  __packages_list_file__ \
  __buildtrees_root__ \
  __override_sources__ \
  "${VCPKG_DEBUG_REUSE_OUTPUTS}"

vcpkg_args=(
  build
  __build_target_name__
  --vcpkg-root=__vcpkg_root__
  --overlay-triplets=__overlay_tripplets__
  --x-buildtrees-root="${buildtrees_tmp}"
  --downloads-root="${buildtrees_tmp}/downloads"
  --x-install-root="${install_root_tmp}"
  --x-packages-root="${packages_dir}"
  --x-asset-sources="x-script,${VCPKG_EXEC_ROOT}/__assets__/__package_name__/get_asset.sh --dst {dst} --sha512 {sha512}"
)

if [[ "${VCPKG_DEBUG}" == 1 ]]; then 
  "${vcpkg_bin}" "${vcpkg_args[@]}"
  if [[ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]]; then 
    set +e
  fi
else
  "${vcpkg_bin}" "${vcpkg_args[@]}" 2>&1 1>/dev/null 
fi

retVal=$?

if [ "${VCPKG_DEBUG}" == 1 ] && [ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]; then 
  if [ $retVal -ne 0 ]; then
    rm -rf "${packages_dir}"
    exit $retVal
  fi
  set -e
fi

__validate_package_output_bin__ \
  "${packages_dir}/__package_output_basename__" \
  "__port_root__"

if [ "${VCPKG_DEBUG}" == 1 ] && [ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]; then
  cp -r "${packages_dir}/__package_output_basename__" "__package_output_dir__"
else
  mv "${packages_dir}/__package_output_basename__" "__package_output_dir__"
fi
