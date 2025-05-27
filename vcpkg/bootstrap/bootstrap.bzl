load("//vcpkg/bootstrap:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap:vcpkg_exec.bzl", "vcpkg_exec")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_VCPKG_WRAPPER = """\
#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname "$0")

exec "${SCRIPT_DIR}/vcpkg/vcpkg" "$@"
"""

_BUILD_BAZEL_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_build", "vcpkg_lib")
load("@rules_vcpkg//vcpkg/toolchain:toolchain.bzl", "vcpkg_toolchain")

vcpkg_toolchain(
    name = "vcpkg",
    vcpkg_tool = "vcpkg_wrapper.sh",
    vcpkg_manifest = ":vcpkg.json",
    vcpkg_files = [
        "//vcpkg:vcpkg",
        "//vcpkg:LICENSE.txt",
        "//vcpkg:.vcpkg-root",
        "//vcpkg/scripts",
        "//vcpkg/triplets",
        "//vcpkg/downloads:tools",
    ],
    host_cpu_count = {host_cpu_count},
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

{packages}\
"""

_VCPKG_PACKAGE_TPL = """\
vcpkg_build(
    name = "{package}_build",
    package_name = "{package}",
    port = "@vcpkg//vcpkg/ports:{package}",
    buildtree = "@vcpkg//vcpkg/buildtrees:{package}",
    downloads = "@vcpkg//vcpkg/downloads:{package}",
    deps = [{build_deps}],
    cpus = "{cpus}",
)

vcpkg_lib(
    name = "{package}",
    build = ":{package}_build",
    deps = [{lib_deps}],
    visibility = ["@vcpkg_{package}//:__subpackages__"],
)
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

_DOWNLOADS_BAZEL_TPL = """\
filegroup(
    name = "tools",
    srcs = glob(["tools/**/*"]),
    visibility = ["//visibility:public"],
)

{packages_downloads}\
"""

_PACKAGE_DOWNLOAD_TPL = """\
filegroup(
    name = "{package_name}",
    srcs = [{downloads}],
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

def _extract_downloads(rctx, output):
    result = {}
    for buildtree in rctx.path("%s/vcpkg/buildtrees" % output).readdir():
        downloads = []
        for buildtree_inner in buildtree.readdir():
            if buildtree_inner.basename.endswith(".log"):
                if buildtree_inner.basename.startswith("stdout"):
                    buildtree_log_content = rctx.read(buildtree_inner)
                    for line in buildtree_log_content.split("\n"):
                        if line.startswith("Successfully downloaded "):
                            downloads.append(line[24:].strip())
                            # download_parts = line.split("->")
                            # if len(download_parts) == 2:
                            #     downloads.append(download_parts[1].strip())
                            # else:
                            #     fail("Can't parse downloads for package: %s parts: %s\n%s" % (
                            #         buildtree.basename,
                            #         download_parts,
                            #         buildtree_log_content,
                            #     ))

                rctx.delete(buildtree_inner)

        result[buildtree.basename] = downloads

    return result

def _format_inner_list(deps, pattern):
    if not deps:
        return ""

    result = [
        "       \"%s\"," % (pattern % dep)
        for dep in deps
    ]

    return "\n" + "\n".join(result) + "\n    "

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

    rctx.file(
        "vcpkg.json",
        json.encode_indent({
            "dependencies": packages.keys(),
        }),
    )

    rctx.file(
        "vcpkg_wrapper.sh",
        _VCPKG_WRAPPER,
        executable = True,
    )

    vcpkg_exec(
        rctx,
        "install",
        ["--only-downloads"],
        output,
    )

    downloads_per_package = _extract_downloads(rctx, output)

    depend_info = collect_depend_info(
        rctx,
        output,
        packages.keys(),
    )

    rctx.file("BUILD.bazel", _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
        host_cpu_count = pu.host_cpus_count(),
        packages = "\n".join([
            _VCPKG_PACKAGE_TPL.format(
                package = package,
                build_deps = _format_inner_list(deps, ":%s_build"),
                lib_deps = _format_inner_list(deps, ":%s"),
                cpus = "1" if not package in packages else packages[package],
            )
            for package, deps in depend_info.items()
        ]),
    ))

    rctx.file("vcpkg/BUILD.bazel", _VCPKG_BAZEL)

    rctx.file("vcpkg/downloads/BUILD.bazel", _DOWNLOADS_BAZEL_TPL.format(
        packages_downloads = "\n".join([
            _PACKAGE_DOWNLOAD_TPL.format(
                package_name = package_name,
                downloads = _format_inner_list(downloads, "%s"),
            )
            for package_name, downloads in downloads_per_package.items()
        ]),
    ))
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
        "packages": attr.string_dict(
            mandatory = True,
            doc = "Packages to install",
        ),
        "sha256": attr.string(
            mandatory = False,
            doc = "SHA256 sum of release archive",
        ),
    },
)
