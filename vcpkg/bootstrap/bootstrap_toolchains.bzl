load("//vcpkg/bootstrap:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_BUILD_BAZEL = """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(
    name = "root",
    srcs = glob(
        [ "**" ],
        exclude = [ "bin/**" ],
    ),
    visibility = ["//visibility:public"],
)
"""

_BIN_BUILD_BAZEL = """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(
    name = "bin",
    srcs = glob([ "**" ]),
    visibility = ["//visibility:public"],
)
"""

def _bootstrap_toolchains_impl(rctx):
    if rctx.os.name.startswith("mac"):
        rctx.download_and_extract(
            url = "https://github.com/Kitware/CMake/releases/download/v4.0.2/cmake-4.0.2-macos-universal.tar.gz",
            sha256 = "4c53ba41092617d1be2205dbc10bb5873a4c5ef5e9e399fc927ffbe78668a6d3",
            strip_prefix = "cmake-4.0.2-macos-universal/CMake.app/Contents",
            output = "cmake",
        )
        rctx.download_and_extract(
            url = "https://github.com/ninja-build/ninja/releases/download/v1.13.0/ninja-mac.zip",
            sha256 = "229314c7ef65e9c11d19f84e5f4bb374105a4f21f64ed55e8f403df765ab52a7",
            output = "bin",
        )
        if rctx.os.arch == "aarch64":
            rctx.download_and_extract(
                url = "https://github.com/uutils/coreutils/releases/download/0.1.0/coreutils-0.1.0-aarch64-apple-darwin.tar.gz",
                sha256 = "7d8068f3d11278d96f78eb42b67d240bb8fb2386724ea597481e97ec75265d9c",
                strip_prefix = "coreutils-0.1.0-aarch64-apple-darwin",
                output = "coreutils",
            )
            rctx.download_and_extract(
                url = "https://github.com/skaji/relocatable-perl/releases/download/5.40.1.0/perl-darwin-arm64.tar.xz",
                sha256 = "e58b98338bc52f352dc95310363ab6c725897557512b90b593c70ea357f1b2ab",
                strip_prefix = "perl-darwin-arm64",
                output = "perl",
            )

            # rctx.download_and_extract(
            #     url = "https://github.com/astral-sh/python-build-standalone/releases/download/20250702/cpython-3.11.13+20250702-x86_64-apple-darwin-install_only_stripped.tar.gz",
            #     sha256 = "7e9a250b61d7c5795dfe564f12869bef52898612220dfda462da88cdcf20031c",
            #     strip_prefix = "python",
            # )
            rctx.extract(
                archive = Label("//vcpkg/bootstrap/archives:arm64/autoconf.zip"),
                strip_prefix = "autoconf",
            )
            rctx.extract(
                archive = Label("//vcpkg/bootstrap/archives:arm64/automake.zip"),
                strip_prefix = "automake",
            )
            rctx.extract(
                archive = Label("//vcpkg/bootstrap/archives:arm64/libtool.zip"),
                strip_prefix = "libtool",
            )
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/m4.zip"))
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/bison.zip"))
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/flex.zip"))
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/make.zip"))
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/autoconf_archive.zip"))
            rctx.extract(
                archive = Label("//vcpkg/bootstrap/archives:arm64/pkgconfig.zip"),
                strip_prefix = "pkgconfig",
            )
        else:
            fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))
    else:
        fail("Unsupported OS: %s" % rctx.os.arch)

    # rctx.file("cmake/BUILD.bazel", _CMAKE_BUILD_FILE)
    # rctx.file("coreutils/BUILD.bazel", _COREUTILS_BUILD_FILE)
    # rctx.file("perl/BUILD.bazel", _PERL_BUILD_FILE)
    # rctx.file("autoconf/BUILD.bazel", _AUTOCONF_BUILD_FILE)
    # rctx.file("automake/BUILD.bazel", _AUTOMAKE_BUILD_FILE)
    # rctx.file("libtool/BUILD.bazel", _LIBTOOL_BUILD_FILE)

    rctx.symlink("/bin/bash", "bin/bash")
    rctx.symlink("/bin/sh", "bin/sh")
    rctx.symlink("/usr/bin/git", "bin/git")
    rctx.symlink("/usr/bin/grep", "bin/grep")
    rctx.symlink("/usr/bin/sed", "bin/sed")
    rctx.symlink("/usr/bin/cmp", "bin/cmp")
    rctx.symlink("/usr/bin/awk", "bin/awk")
    rctx.symlink("/usr/bin/vm_stat", "bin/vm_stat")
    rctx.symlink("/usr/bin/find", "bin/find")

    rctx.symlink("/usr/sbin/zic", "bin/zic")
    rctx.symlink("/opt/homebrew/bin/gsed", "bin/gsed")
    # rctx.symlink("/opt/homebrew/bin/gettext", "bin/gettext")

    if rctx.os.name.startswith("mac"):
        rctx.symlink("/usr/sbin/sysctl", "bin/sysctl")
        rctx.symlink("/usr/bin/otool", "bin/otool")
        rctx.symlink("/usr/bin/file", "bin/file")
        rctx.symlink("/usr/bin/install_name_tool", "bin/install_name_tool")
        rctx.symlink("/usr/bin/codesign", "bin/codesign")

        # rctx.symlink("/usr/bin/libtool", "bin/libtool")
        rctx.symlink("/usr/bin/ranlib", "bin/ranlib")
        rctx.symlink("/usr/bin/ar", "bin/ar")
        rctx.symlink("/usr/bin/lipo", "bin/lipo")

        # TODO: support hermetic
        rctx.symlink("/usr/bin/clang", "bin/clang")
        rctx.symlink("/usr/bin/clang++", "bin/clang++")
        rctx.symlink("/usr/bin/python3", "bin/python3")
    else:
        fail("Unsupported OS: %s" % rctx.os.arch)

    def symlink_rel(target, link_name):
        exec_check(rctx, "symlink", ["coreutils/coreutils", "ln", "-s", target, link_name])

    symlink_rel("../cmake/bin/cmake", "bin/cmake")
    symlink_rel("../perl/bin/perl", "bin/perl")

    coretools_res, err = exec_check(rctx, "list coreutils", ["coreutils/coreutils", "--list"])
    if err:
        fail(err)

    for coretool in coretools_res.stdout.split("\n"):
        coretool = coretool.strip()
        if coretool in ["[", ""]:
            continue

        symlink_rel("../coreutils/coreutils", "bin/%s" % coretool)

    # def symlink_all_bins(dir):
    #     for bin in rctx.path("%s/bin" % dir).readdir():
    #         symlink_rel(
    #             "../%s/bin/%s" % (dir, bin.basename),
    #             "bin/%s" % bin.basename,
    #         )

    # symlink_all_bins("autoconf")
    # symlink_all_bins("automake")
    # symlink_all_bins("libtool")

    rctx.file(
        "BUILD.bazel",
        _BUILD_BAZEL,
    )

    rctx.file(
        "bin/BUILD.bazel",
        _BIN_BUILD_BAZEL,
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    else:
        return None

bootstrap_toolchains = repository_rule(
    implementation = _bootstrap_toolchains_impl,
)
