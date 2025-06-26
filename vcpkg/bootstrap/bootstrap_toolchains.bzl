load("//vcpkg/bootstrap:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

# _CMAKE_BUILD_FILE = """\
# filegroup(
#     name = "cmake_data",
#     srcs = glob(
#         [ "**" ],
#         exclude = [
#             "WORKSPACE",
#             "WORKSPACE.bazel",
#             "BUILD",
#             "BUILD.bazel",
#             "**/* *",
#         ],
#     ),
#     visibility = ["//:__pkg__"],
# )
# """

# _COREUTILS_BUILD_FILE = """\
# filegroup(
#     name = "coreutils_data",
#     srcs = [ "coreutils" ],
#     visibility = [ "//:__pkg__" ],
# )
# """

# _PERL_BUILD_FILE = """\
# filegroup(
#     name = "perl_data",
#     srcs = glob(["**/*"]),
#     visibility = [ "//:__pkg__" ],
# )
# """

# _AUTOCONF_BUILD_FILE = """\
# filegroup(
#     name = "autoconf_data",
#     srcs = glob(["**/*"]),
#     visibility = [ "//:__pkg__" ],
# )
# """

# _AUTOMAKE_BUILD_FILE = """\
# filegroup(
#     name = "automake_data",
#     srcs = glob(["**/*"]),
#     visibility = [ "//:__pkg__" ],
# )
# """

# _LIBTOOL_BUILD_FILE = """\
# filegroup(
#     name = "libtool_data",
#     srcs = glob(["**/*"]),
#     visibility = [ "//:__pkg__" ],
# )
# """

VcpgExternalInfo = provider(
    doc = "Information about external binaries used with vcpkg toolchain.",
    fields = [
        "binaries",
        "transitive",
    ],
)

def _vcpkg_external_toolchain_impl(ctx):
    return platform_common.ToolchainInfo(
        vcpkg_external_info = VcpgExternalInfo(
            binaries = depset(ctx.files.binaries),
            transitive = depset(ctx.files.transitive),
        ),
    )

vcpkg_external_toolchain = rule(
    implementation = _vcpkg_external_toolchain_impl,
    attrs = {
        "binaries": attr.label_list(
            allow_files = True,
            doc = "Path to the binaries",
        ),
        "transitive": attr.label_list(
            allow_files = True,
            doc = "Transitive external toolchains files",
        ),
    },
)

_BUILD_BAZEL_TPL = """\
load("@rules_vcpkg//vcpkg/bootstrap:bootstrap_toolchains.bzl", "vcpkg_external_toolchain")

vcpkg_external_toolchain(
    name = "vcpkg_external",
    binaries = glob([ "bin/**" ]),
    transitive = glob(
        [ "**/*" ],
        exclude = [
            "bin/**",
            "**/*.bazel",
            "**/* *",
        ],    
    ),
)

toolchain(
    name = "vcpkg_external_toolchain",
    exec_compatible_with = [
        "{os}",
        "{arch}",
    ],
    target_compatible_with = [
        "{os}",
        "{arch}",
    ],
    toolchain = ":vcpkg_external",
    toolchain_type = "@rules_vcpkg//vcpkg/toolchain:external_toolchain_type",
    visibility = ["//visibility:public"],
)
"""

def _bootstrap_toolchains_impl(rctx):
    pu = platform_utils(rctx)

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
            rctx.extract(Label("//vcpkg/bootstrap/archives:arm64/make.zip"))
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

    # rctx.symlink("/usr/bin/python3", "bin/python3")
    rctx.symlink("/opt/homebrew/bin/gsed", "bin/gsed")
    # rctx.symlink("/opt/homebrew/bin/gettext", "bin/gettext")

    if rctx.os.name.startswith("mac"):
        rctx.symlink("/usr/sbin/sysctl", "bin/sysctl")
        rctx.symlink("/usr/bin/otool", "bin/otool")
        rctx.symlink("/usr/bin/file", "bin/file")
        rctx.symlink("/usr/bin/install_name_tool", "bin/install_name_tool")

        # rctx.symlink("/usr/bin/libtool", "bin/libtool")
        rctx.symlink("/usr/bin/ranlib", "bin/ranlib")
        rctx.symlink("/usr/bin/ar", "bin/ar")

        # TODO: support hermetic
        rctx.symlink("/usr/bin/clang", "bin/clang")
        rctx.symlink("/usr/bin/clang++", "bin/clang++")
    else:
        fail("Unsupported OS: %s" % rctx.os.arch)

    def symlink_rel(target, link_name):
        exec_check(rctx, "symlink", ["coreutils/coreutils", "ln", "-s", target, link_name])

    symlink_rel("../cmake/bin/cmake", "bin/cmake")
    symlink_rel("../perl/bin/perl", "bin/perl")

    for coretool in exec_check(rctx, "list coreutils", ["coreutils/coreutils", "--list"]).stdout.split("\n"):
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
        _BUILD_BAZEL_TPL.format(
            os = pu.targets.os,
            arch = pu.targets.arch,
        ),
    )

bootstrap_toolchains = repository_rule(
    implementation = _bootstrap_toolchains_impl,
)
