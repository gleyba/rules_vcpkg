# Build [QT VCPKG package](https://vcpkg.io/en/package/qt) with `rules_vcpk`

[!WARNING] 
This package is very heavyweight, requores non-release VCPK distribution (because requires most recent fixes), custom patches to ports and hermetic MacosSDK.

All of thes make this package too heavyweight and risk of build error to high after 550 packages built out of 650 and now you need to reinitialize workspace.

For debug purposes, better to run with such lines in `.user.bazelrc`:

    build --@rules_vcpkg//:debug=True
    build --@rules_vcpkg//:debug_reuse_outputs=True
    build --noincompatible_sandbox_hermetic_tmp

Probably it is just not a good idea to build this with Bazel. 
But I choose it as a goal and prove maturity of the toolchain.
So spent endless hours on it, but fixed lots and lots of bugs and inefficiencies.

## Done and Upcoming work

- [x] Test on Macos arm64
- [ ] Test on Linux x86_64
- [ ] Test on Linux arm64