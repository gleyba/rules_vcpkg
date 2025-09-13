#!/usr/bin/env bash

set -eu pipefail

__exports__

vcpkg_bin="${PWD}/__vcpkg_bin__"
prepare_install_dir_bin="${PWD}/__prepare_install_dir_bin__"
validate_package_output_bin="${PWD}/__validate_package_output_bin__"

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

"${prepare_install_dir_bin}" \
  "${buildtrees_tmp}" \
  __prepare_install_dir_cfg__

vcpkg_args=(
  build
  __build_target_name__
  --vcpkg-root=__vcpkg_root__
  --overlay-triplets=__overlay_tripplets__
  --x-buildtrees-root="${buildtrees_tmp}"
  --downloads-root="${buildtrees_tmp}/downloads"
  --x-install-root="${buildtrees_tmp}/install"
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

"${validate_package_output_bin}" \
  "${packages_dir}/__package_output_basename__" \
  __validate_package_output_cfg__

if [ "${VCPKG_DEBUG}" == 1 ] && [ "${VCPKG_DEBUG_REUSE_OUTPUTS}" == 1 ]; then
  cp -r "${packages_dir}/__package_output_basename__" "__package_output_dir__"
else
  mv "${packages_dir}/__package_output_basename__" "__package_output_dir__"
fi
