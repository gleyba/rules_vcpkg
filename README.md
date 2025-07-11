# VCPKG rules for Bazel

This is a very draft of how [vcpkg](https://vcpkg.io/en/) dependency manager can be integrated to [Bazel](https://bazel.build/) build system.

Vcpkg is the well curated list of C/C++ libraries with predefined configurations to build from source.
It is easy to integrate if you use Cmake, but Bazel is a separate story.

You can `cc_import` libraries produced by vcpkg, but you have to manage two different systems in conjunction with each other.

The main goal of `rules_vcpkg` is to wrap `vcpkg` as a hermetic toolchain for Bazel, and provide an easy way to declare package with Bazel's [bzlmod](https://bazel.build/external/overview) module system.

Initial vcpkg bootstrap with all declared packages implemented as a [repository rule](https://bazel.build/external/repo). But each library build process is a separate execution phase [action](https://bazel.build/extending/rules#actions) wrapped in custom [rule](https://bazel.build/extending/rules). 

Such a setup must be compatible with Bazel's remote caching and remote execution.

Somewhat similar in nature to how [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) implemented, but here we don't need to define complex configurations, all is done by vcpkg itself. 

All we need is to provide a buildtree and transitive dependencies collected with a directory structure compatible to `vcpkg build <package_name>` invocation. 

Which is done by bunch of hacks as a proof-of-concept.

## Getting started

There is `examples` directory, which I'm going to extend.
But to try yourself this early draft, add to `MODULE.bazel`:

```
bazel_dep("rules_vcpkg", version = "over 9000")
git_override(
    module_name = "rules_vcpkg", 
    remote = "https://github.com/gleyba/rules_vcpkg",
    branch = "master",
)

vcpkg = use_extension("@rules_vcpkg//vcpkg:extensions.bzl", "vcpkg")
vcpkg.bootstrap(
    release = "2025.04.09",
    sha256 = "9a129eb4206157a03013dd87805406ef751a892170eddcaaf94a9b5db8a89b0f",
)

vcpkg.install(package = "fmt")
use_repo(vcpkg, "vcpkg")
use_repo(vcpkg, "vcpkg_fmt")

register_toolchains("@vcpkg//:vcpkg_toolchain")
```

Then, in `BUILD.bazel`:

```
cc_binary(
    name = "hello_fmt",
    srcs = ["hello_fmt.cpp"],
    deps = ["@vcpkg_fmt//:fmt"],
)
```

And `hello_fmt.cpp`:

```
#include <fmt/core.h>

int main() {
    fmt::print("Hello FMT!\n");
}
```

Run it as:

```
bazel run //:hello_fmt
INFO: Analyzed target //:hello_fmt (89 packages loaded, 9927 targets configured).
INFO: Found 1 target...
Target //:hello_fmt up-to-date:
  bazel-bin/hello_fmt
INFO: Elapsed time: 1.630s, Critical Path: 0.05s
INFO: 1 process: 41 action cache hit, 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/hello_fmt
Hello FMT!
```

## Debugging

- `--@rules_vcpkg//:debug=True`
    If set, will print VCPKG output for packages build.
    Also will initialize build tree in `/tmp/vcpkg/builtrees/<package_name>` dir.

- `--@rules_vcpkg//:debug_reuse_outputs=True`
    If set and build outputs exist in `/tmp/vcpkg/builtrees/<package_name>` dir,
    will reuse these outputs instead of running build.

## Done and Upcoming work

- Test more sophisticated packages with complex transitive dependencies structure:
    - [x] Add [FMT](https://github.com/fmtlib/fmt) example
    - [x] Add [Boost.Asio](https://www.boost.org/doc/libs/latest/doc/html/boost_asio.html) example
    - [x] Add [Facebook Folly](https://github.com/facebook/folly) example
    - [x] Add [DuckDB](https://duckdb.org) example
    - [ ] Add [QT](https://www.qt.io/) example
    - [ ] Add [AWS C++ SDK](https://github.com/aws/aws-sdk-cpp) example
    - [ ] Add [Google Cloud Cpp](https://github.com/googleapis/google-cloud-cpp) example
    - [ ] Add [Azure SDK for Cpp](https://github.com/Azure/azure-sdk-for-cpp/tree/main) example
- Prepare additional toolchains done via [rules_vcpkg_externals](https://github.com/gleyba/rules_vcpkg_externals):
    - [x] make
    - [x] m4
    - [x] bison
    - [x] flex
    - [x] pkgconfig
    - [x] autoconf
    - [x] autoconf-archive
    - [x] automake
    - [x] libtoolize
    - [x] gsed
    - [ ] zic (do we need it?)
    - [ ] gettext (do we need it?)
- Support other platforms besides Mac OS X aarh64: 
    - [ ] Compile everything for MacOS x86_64
    - [ ] Compile everything for Linux Arm64
    - [ ] Compile everything for Linux x86_64
- Setup CI checks:
    - [ ] Release `rules_vcpkg_externals` artifacts to github packages
    - [ ] Setup simple build examples CI checks
- Hermeticity and reproducibility:
    - [x] Some work done and packages build are mostly cacheable from disk cache
    - [x] Use of [VCPKG assetcaching](https://learn.microsoft.com/en-us/vcpkg/users/assetcaching?WT.mc_id=vcpkg_inproduct_cli) to integrate packages downloads with Bazel downloader
    - [x] Hermetic Mac OS X SDK from [joseluisq/macosx-sdks](https://github.com/joseluisq/macosx-sdks)
    - [ ] Do more comprehensive cache hit/miss analysis
- Support hermetic C/C++ Bazel toolchains by generating custom [Overlay Triplet](https://learn.microsoft.com/en-us/vcpkg/users/examples/overlay-triplets-linux-dynamic) with [VCPKG_CHAINLOAD_TOOLCHAIN_FILE](https://learn.microsoft.com/en-us/vcpkg/users/triplets#vcpkg_chainload_toolchain_file):
    - [x] Overlay tripplet used as entry point to propagate custom configuration to VCPKG/Cmake
    - [ ] Setup chainload file for c/c++ toolchain
- [ ] Test with remote build execution
- [ ] Announce this work in Bazel slack
