load("//vcpkg/private:vcpkg_build.bzl", _vcpkg_build = "vcpkg_build")
load("//vcpkg/private:vcpkg_lib.bzl", _vcpkg_lib = "vcpkg_lib")
load("//vcpkg/private:vcpkg_package.bzl", _vcpkg_package = "vcpkg_package")

vcpkg_build = _vcpkg_build
vcpkg_lib = _vcpkg_lib
vcpkg_package = _vcpkg_package
