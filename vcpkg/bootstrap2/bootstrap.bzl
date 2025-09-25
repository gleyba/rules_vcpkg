load("//vcpkg/bootstrap2:configure.bzl", "BOOTSTRAP_CONFIGURE_REPO_ATTRS", "new_bootstrap_configure_ctx")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "format_additions", "format_inner_dict", "format_inner_list")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

def _download_vcpkg_tool(rctx, pu):
    rctx.report_progress("Downloading VCPKG tool")

    tool_meta = {
        line.split("=")[0]: line.split("=")[1]
        for line in rctx.read("vcpkg/scripts/vcpkg-tool-metadata.txt").split("\n")
        if line
    }

    rctx.download(
        url = pu.downloads.url_tpl % tool_meta["VCPKG_TOOL_RELEASE_TAG"],
        output = "vcpkg/vcpkg",
        integrity = "sha512-%s" % base64_encode_hexstr(tool_meta[pu.downloads.sha_key]),
        executable = True,
    )

_VCPKG_WRAPPER = """\
#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname "$0")

exec "${SCRIPT_DIR}/vcpkg/vcpkg" "$@"
"""

def _initialize(rctx, pu):
    rctx.report_progress("VCPKG: Initializing")

    rctx.file(
        "vcpkg_wrapper.sh",
        _VCPKG_WRAPPER,
        executable = True,
    )

    rctx.template(
        "overlay_triplets/%s.cmake" % pu.definitions.triplet,
        pu.triplet_template,
        substitutions = pu.definitions.substitutions | format_additions(
            {},
            rctx.attr.config_settings,
        ),
    )

_BUILD_BAZEL_TPL = """\
load("@rules_vcpkg//vcpkg/toolchain:toolchain.bzl", "vcpkg_toolchain")

filegroup(
    name = "all_files",
    srcs = [
        "vcpkg_wrapper.sh",
        "//vcpkg:vcpkg",
        "//vcpkg:LICENSE.txt",
        "//vcpkg:.vcpkg-root",
        "//vcpkg/scripts",
        "//vcpkg/triplets",
        "//vcpkg/ports",
    ],
)

vcpkg_toolchain(
    name = "vcpkg",
    vcpkg_tool = "vcpkg_wrapper.sh",
    vcpkg_files = [
        "//vcpkg:vcpkg",
        "//vcpkg:LICENSE.txt",
        "//vcpkg:.vcpkg-root",
        "//vcpkg/scripts",
        "//vcpkg/triplets",
    ],
    config_settings = {config_settings},
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
)\
"""

_VCPKG_BAZEL = """\
exports_files(
    srcs = [
        "vcpkg",
        ".vcpkg-root",
        "LICENSE.txt",
    ],
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

_PORTS_BAZEL_TPL = """\
filegroup(
    name = "ports",
    srcs = {ports},
    visibility = ["//visibility:public"],
)
"""

_PORT_BAZEL_TPL = """\
filegroup(
    name = "{port}",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)
"""

def _write_templates(rctx, pu):
    rctx.file("BUILD.bazel", _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
        config_settings = format_inner_dict(rctx.attr.config_settings),
    ))

    rctx.file("vcpkg/BUILD.bazel", _VCPKG_BAZEL)
    rctx.file("vcpkg/scripts/BUILD.bazel", _SCRIPTS_BAZEL)
    rctx.file("vcpkg/triplets/BUILD.bazel", _TRIPLETS_BAZEL)

    ports = [p.basename for p in rctx.path("vcpkg/ports").readdir()]

    rctx.file(
        "vcpkg/ports/BUILD.bazel",
        _PORTS_BAZEL_TPL.format(
            ports = format_inner_list(
                ports,
                pattern = "\"{dep}\"",
            ),
        ),
    )

    for port in ports:
        rctx.file(
            "vcpkg/ports/%s/BUILD.bazel" % port,
            _PORT_BAZEL_TPL.format(port = port),
        )

def _bootrstrap_impl(rctx):
    if rctx.attr.release and rctx.attr.commit:
        fail("Both 'release' or 'commit' arguments specified, only one needed to bootstrap vcpkg")
    elif rctx.attr.release:
        rctx.download_and_extract(
            url = "https://github.com/microsoft/vcpkg/archive/refs/tags/%s.tar.gz" % rctx.attr.release,
            output = "vcpkg",
            strip_prefix = "vcpkg-%s" % rctx.attr.release,
            sha256 = rctx.attr.sha256,
        )
    elif rctx.attr.commit:
        rctx.download_and_extract(
            url = "https://github.com/microsoft/vcpkg/archive/%s.zip" % rctx.attr.commit,
            output = "vcpkg",
            strip_prefix = "vcpkg-%s" % rctx.attr.commit,
            sha256 = rctx.attr.sha256,
        )
    else:
        fail("No 'release' or 'commit' argument specified, either one needed to bootstrap vcpkg")

    pu = platform_utils(rctx)

    _download_vcpkg_tool(rctx, pu)
    _initialize(rctx, pu)
    _write_templates(rctx, pu)

    bootstrap_configure_ctx = new_bootstrap_configure_ctx()
    bootstrap_configure_ctx.fill_from_repo_ctx(rctx)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    else:
        return None

bootstrap = repository_rule(
    implementation = _bootrstrap_impl,
    attrs = {
        "release": attr.string(
            doc = "The vcpkg version, either this or commit must be specified",
        ),
        "commit": attr.string(
            doc = "The vcpkg commit, either this of version must be specified",
        ),
        "sha256": attr.string(
            mandatory = False,
            doc = "SHA256 sum of release archive",
        ),
        "lockfile": attr.label(
            doc = "Json file to lock packages dependencies",
            mandatory = True,
        ),
        "config_settings": attr.string_dict(
            doc = "Vcpkg triplet configuration settings",
            mandatory = True,
        ),
    } | BOOTSTRAP_CONFIGURE_REPO_ATTRS,
)
