load("//vcpkg/bootstrap:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_CMAKE_BUILD_FILE = """\
filegroup(
    name = "cmake_data",
    srcs = glob(
        [ "**" ],
        exclude = [
            "WORKSPACE",
            "WORKSPACE.bazel",
            "BUILD",
            "BUILD.bazel",
            "**/* *",
        ],
    ),
    visibility = ["//:__pkg__"],
)
"""

_COREUTILS_BUILD_FILE = """\
filegroup(
    name = "coreutils_data",
    srcs = [ "coreutils" ],
    visibility = [ "//:__pkg__" ],
)
"""

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
    transitive = [
        "//cmake:cmake_data",
        "//coreutils:coreutils_data",
    ],
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
        if rctx.os.arch == "aarch64":
            rctx.download_and_extract(
                url = "https://github.com/uutils/coreutils/releases/download/0.1.0/coreutils-0.1.0-aarch64-apple-darwin.tar.gz",
                sha256 = "7d8068f3d11278d96f78eb42b67d240bb8fb2386724ea597481e97ec75265d9c",
                strip_prefix = "coreutils-0.1.0-aarch64-apple-darwin",
                output = "coreutils",
            )
        else:
            fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    else:
        fail("Unsupported OS: %s" % rctx.os.arch)

    rctx.file("cmake/BUILD.bazel", _CMAKE_BUILD_FILE)
    rctx.file("coreutils/BUILD.bazel", _COREUTILS_BUILD_FILE)

    rctx.symlink("/bin/bash", "bin/bash")
    rctx.symlink("/bin/sh", "bin/sh")
    rctx.symlink("/usr/bin/git", "bin/git")

    if rctx.os.name.startswith("mac"):
        rctx.symlink("/usr/sbin/sysctl", "bin/sysctl")
        rctx.symlink("/usr/bin/otool", "bin/otool")
        rctx.symlink("/usr/bin/file", "bin/file")
        rctx.symlink("/usr/bin/install_name_tool", "bin/install_name_tool")

        # TODO: support hermetic
        rctx.symlink("/usr/bin/clang", "bin/clang")
        rctx.symlink("/usr/bin/clang++", "bin/clang++")
    else:
        fail("Unsupported OS: %s" % rctx.os.arch)

    def symlink_rel(target, link_name):
        exec_check(rctx, "symlink", ["coreutils/coreutils", "ln", "-s", target, link_name])

    symlink_rel("../cmake/bin/cmake", "bin/cmake")

    for coretool in exec_check(rctx, "list coreutils", ["coreutils/coreutils", "--list"]).stdout.split("\n"):
        coretool = coretool.strip()
        if coretool in ["[", ""]:
            continue

        symlink_rel("../coreutils/coreutils", "bin/%s" % coretool)

    rctx.file("BUILD.bazel", _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
    ))

bootstrap_toolchains = repository_rule(
    implementation = _bootstrap_toolchains_impl,
)
