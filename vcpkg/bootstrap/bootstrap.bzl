load("//vcpkg/bootstrap:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap:vcpkg_exec.bzl", "vcpkg_exec")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_BUILD_BAZEL_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_build")
load("@rules_vcpkg//vcpkg/toolchain:toolchain.bzl", "vcpkg_toolchain")

vcpkg_toolchain(
    name = "vcpkg",
    vcpkg_tool = "//vcpkg",
    default_install_files = [
        "//install",
    ],
    vcpkg_files = [
        "//vcpkg",
        "//vcpkg/scripts",
        "//vcpkg/triplets",
        "//vcpkg/downloads",
    ],
)

toolchain(
    name = "vcpkg_toolchain",
    exec_compatible_with = [
        "{os}",
        "{arch}",
    ],
    target_compatible_with = [
        "{os}",
        "{arch}",
    ],
    toolchain = ":vcpkg",
    toolchain_type = "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
    visibility = ["//visibility:public"],
)

{packages}
"""

_VCPKG_PACKAGE_TPL = """\
vcpkg_build(
    name = "{package}",
    port = "@vcpkg//vcpkg/ports:{package}",
    buildtree = "@vcpkg//vcpkg/buildtrees:{package}",
    deps = [
{deps}
    ],
    visibility = ["//visibility:public"],
)
"""

_VCPKG_BAZEL = """\
filegroup(
    name = "vcpkg_tool",
    srcs = ["vcpkg"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "vcpkg",
    srcs = [
        ":vcpkg_tool",
        "vckpg.json",
    ],
    visibility = ["//visibility:public"],
)
"""

_INSTALL_BAZEL = """\
filegroup(
    name = "install",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)
"""

_DOWNLOADS_BAZEL = """\
filegroup(
    name = "downloads",
    srcs = glob(["tools/**/*"]),
    visibility = ["//visibility:public"],
)
"""

_SCRIPTS_BAZEL = """\
filegroup(
    name = "scripts",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)
"""

_TRIPLETS_BAZEL = """\
filegroup(
    name = "triplets",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)
"""

_PORT_BAZEL_TPL = """\
filegroup(
    name = "{port}",
    srcs = glob(["{port}/**/*"]),
    visibility = ["//visibility:public"],
)
"""

def _bootstrap(rctx, output, release, sha256, packages):
    pu = platform_utils(rctx)

    rctx.download_and_extract(
        url = "https://github.com/microsoft/vcpkg/archive/refs/tags/%s.tar.gz" % release,
        output = "%s/vcpkg" % output,
        strip_prefix = "vcpkg-%s" % release,
        sha256 = sha256,
    )

    tool_meta = {
        line.split("=")[0]: line.split("=")[1]
        for line in rctx.read("%s/vcpkg/scripts/vcpkg-tool-metadata.txt" % output).split("\n")
        if line
    }

    rctx.download(
        url = pu.downloads.url_tpl % tool_meta["VCPKG_TOOL_RELEASE_TAG"],
        output = "%s/vcpkg/vcpkg" % output,
        integrity = "sha512-%s" % base64_encode_hexstr(tool_meta[pu.downloads.sha_key]),
        executable = True,
    )

    # rctx.file("registries/BUILD.bazel", "")
    # rctx.file("overlay_ports/BUILD.bazel", "")

    # exec_check(
    #     rctx,
    #     "vcpkg bootstrap",
    #     [
    #         "vcpkg/vcpkg",
    #         "bootstrap-standalone"
    #     ] + vcpkg_args,
    #     vcpkg_env,
    # )

    rctx.file(
        "vcpkg.json",
        json.encode_indent({
            "dependencies": packages,
        }),
    )

    vcpkg_exec(
        rctx,
        "install",
        ["--only-downloads"],
        output,
    )

    depend_info = collect_depend_info(
        rctx,
        output,
        packages,
    )

    rctx.file("BUILD.bazel", _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
        packages = "\n".join([
            _VCPKG_PACKAGE_TPL.format(
                package = package,
                deps = "\n".join([
                    "       \":{dep}\",".format(dep = dep)
                    for dep in deps
                ]),
            )
            for package, deps in depend_info.items()
        ]),
    ))

    rctx.file("vcpkg/BUILD.bazel", _VCPKG_BAZEL)
    rctx.file("install/BUILD.bazel", _INSTALL_BAZEL)
    rctx.file("vcpkg/downloads/BUILD.bazel", _DOWNLOADS_BAZEL)
    rctx.file("vcpkg/scripts/BUILD.bazel", _SCRIPTS_BAZEL)
    rctx.file("vcpkg/triplets/BUILD.bazel", _TRIPLETS_BAZEL)
    rctx.file("vcpkg/ports/BUILD.bazel", "\n".join([
        _PORT_BAZEL_TPL.format(port = port)
        for port in depend_info.keys()
    ]))
    rctx.file("vcpkg/buildtrees/BUILD.bazel", "\n".join([
        _PORT_BAZEL_TPL.format(port = port)
        for port in depend_info.keys()
    ]))

def _bootrstrap_impl(rctx):
    _bootstrap(
        rctx,
        output = ".",
        release = rctx.attr.release,
        sha256 = rctx.attr.sha256,
        packages = rctx.attr.packages,
    )

bootstrap = repository_rule(
    implementation = _bootrstrap_impl,
    attrs = {
        "release": attr.string(
            mandatory = True,
            doc = "The vcpkg version",
        ),
        "packages": attr.string_list(
            mandatory = True,
            doc = "Packages to install",
        ),
        "sha256": attr.string(
            mandatory = False,
            doc = "SHA256 sum of release archive",
        ),
    },
)
