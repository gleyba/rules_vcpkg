load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//vcpkg:vcpkg.bzl", "vcpkg_package")
load("//vcpkg/bootstrap:bootstrap.bzl", _bootstrap = "bootstrap")

bootstrap = tag_class(attrs = {
    "release": attr.string(doc = "The vcpkg version"),
    "sha256": attr.string(doc = "Shasum of vcpkg"),
})

install = tag_class(attrs = {
    "package": attr.string(doc = "Package to install"),
    "cpus": attr.string(
        default = "1",
        doc = "Cpu cores to use for package build, accept `HOST_CPUS` keyword",
    ),
})

_CMAKE_BUILD_FILE = """\
filegroup(
    name = "cmake_bin",
    srcs = ["bin/cmkae"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "cmake_data",
    srcs = glob(
        [
            "**",
        ],
        exclude = [
            "WORKSPACE",
            "WORKSPACE.bazel",
            "BUILD",
            "BUILD.bazel",
            "**/* *",
        ],
    ),
    visibility = ["//visibility:public"],
)
"""

def _vcpkg(mctx):
    if mctx.os.name.startswith("mac"):
        http_archive(
            name = "cmake",
            urls = [
                "https://github.com/Kitware/CMake/releases/download/v4.0.2/cmake-4.0.2-macos-universal.tar.gz",
            ],
            sha256 = "4c53ba41092617d1be2205dbc10bb5873a4c5ef5e9e399fc927ffbe78668a6d3",
            strip_prefix = "cmake-4.0.2-macos-universal/CMake.app/Contents",
            build_file_content = _CMAKE_BUILD_FILE,
        )
    else:
        fail("Unsupported OS/arch: %s/%s" % (mctx.os.name, mctx.os.arch))

    cur_bootstrap = None
    packages = {}
    for mod in mctx.modules:
        for bootstrap in mod.tags.bootstrap:
            if cur_bootstrap:
                if cur_bootstrap.release < bootstrap.release:
                    tmp = cur_bootstrap
                    cur_bootstrap = bootstrap
                    bootstrap = tmp

                mctx.report_progress("Skip vcpkg release: %s, using a newer one" % bootstrap.release)
            else:
                cur_bootstrap = bootstrap

        for install in mod.tags.install:
            packages[install.package] = install.cpus

    if not cur_bootstrap:
        fail("No vcpkg release version to bootstrap specified")

    mctx.report_progress("Bootstrapping vcpkg release: %s" % cur_bootstrap.release)

    _bootstrap(
        name = "vcpkg",
        release = cur_bootstrap.release,
        sha256 = cur_bootstrap.sha256,
        packages = packages,
    )

    for package in packages.keys():
        vcpkg_package(
            name = "vcpkg_%s" % package,
            package = package,
        )

vcpkg = module_extension(
    implementation = _vcpkg,
    tag_classes = {
        "bootstrap": bootstrap,
        "install": install,
    },
)
