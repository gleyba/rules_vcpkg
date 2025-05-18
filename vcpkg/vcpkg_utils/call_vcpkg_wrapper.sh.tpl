#!/usr/bin/env bash

set -eu

export HOME=/tmp/home
export PATH="${PWD}/__cmake_bin__:/usr/bin:/bin"

vcpkg_bin="${PWD}/__vcpkg_bin__"
prepare_install_dir_bin="${PWD}/__prepare_install_dir_bin__"

"${prepare_install_dir_bin}" \
  __install_dir_path__ \
  __vcpkg_manifest_path__ \
  __packages_list_file__

"${vcpkg_bin}" \
  build \
  __package_name__ \
  --vcpkg-root=__vcpkg_root__ \
  --x-buildtrees-root=__buildtrees_root__ \
  --downloads-root=__downloads_root__ \
  --x-install-root=__install_root__ \
  --x-packages-root=__packages_root__
