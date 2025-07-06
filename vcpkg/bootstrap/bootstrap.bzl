load("//vcpkg/bootstrap:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap:vcpkg_exec.bzl", "vcpkg_exec")
load("//vcpkg/toolchain:current_toolchain.bzl", "DEFAULT_TRIPLET_SETS", "format_additions")
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
    package_features = [{features}],
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

_DOWNLOAD_TRY_PREFIX = "Trying to download "
_DOWNLOAD_TRY_POSTFIX = " using asset cache script"

def _extract_downloads(rctx, result, output):
    for buildtree in rctx.path("%s/vcpkg/buildtrees" % output).readdir():
        downloads = set()
        for buildtree_inner in buildtree.readdir():
            if buildtree_inner.basename.endswith(".log"):
                if buildtree_inner.basename.startswith("stdout"):
                    buildtree_log_content = rctx.read(buildtree_inner)
                    for line in buildtree_log_content.split("\n"):
                        if not line.startswith(_DOWNLOAD_TRY_PREFIX):
                            continue

                        if not line.endswith(_DOWNLOAD_TRY_POSTFIX):
                            fail("Can't parse try-download line: %s" % line)

                        downloads.add(line[len(_DOWNLOAD_TRY_PREFIX):-len(_DOWNLOAD_TRY_POSTFIX)].strip())

                rctx.delete(buildtree_inner)

        if buildtree.basename in result:
            result[buildtree.basename] |= downloads
        else:
            result[buildtree.basename] = downloads

    return result

_COLLECT_ASSETS_SH = """\
#!/bin/bash

set -eu

cd "$(dirname "$0")"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --url) url="$2"; shift ;;
        --dst) dst="$2"; shift ;;
        --sha512) sha512="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -f "collect_assets/${sha512}" ]; then
    ln "collect_assets/${sha512}" "${dst}"
else
    echo "${url} ${sha512}" >> collect_assets.csv
fi
"""

def _download_deps(rctx, output):
    full_path = str(rctx.path(output))

    rctx.file("collect_assets.sh", _COLLECT_ASSETS_SH, executable = True)

    install_args = [
        "--only-downloads",
        "--x-asset-sources=%s" % ";".join([
            " ".join([
                "x-script,%s/collect_assets.sh" % full_path,
                "--url {url}",
                "--dst {dst}",
                "--sha512 {sha512}",
            ]),
            "x-block-origin",
        ]),
    ]

    downloads = {}

    # Just some number of iterations as a hack, should finish early
    for i in range(16):
        if i == 15:
            fail("\n".join([
                "We ran 'vcpkg install --only-downloads' to collect downloads 15 times,",
                "but didn't collect all, probably we are in corrupted state",
            ]))

        rctx.file("collect_assets.csv", "", executable = False)

        # Call `install --only-downloads` jsut to collect csv with urls and sha512
        vcpkg_exec(rctx, "install", install_args, output)
        if i:
            _extract_downloads(rctx, downloads, output)

        to_download = [
            line.split(" ")
            for line in rctx.read("collect_assets.csv").split("\n")
            if line
        ]
        if not to_download:
            # After last `install --only-downloads` we must have downloads in place
            break

        # Actually download assets
        for url, sha512 in to_download:
            rctx.download(
                url = url,
                output = "collect_assets/%s" % sha512,
                integrity = "sha512-%s" % base64_encode_hexstr(sha512),
            )

    rctx.delete("collect_assets.sh")
    rctx.delete("collect_assets.csv")
    rctx.delete("collect_assets")

    return downloads

def _format_inner_list(deps, pattern):
    if not deps:
        return ""

    result = [
        "       \"%s\"," % (pattern % dep)
        for dep in deps
    ]

    return "\n" + "\n".join(result) + "\n    "

def _bootstrap(rctx, output, packages):
    pu = platform_utils(rctx)

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

    rctx.template(
        "overlay_triplets/%s.cmake" % pu.cmake_definitions.triplet,
        pu.triplet_template,
        substitutions = pu.cmake_definitions.substitutions | format_additions(
            {},
            DEFAULT_TRIPLET_SETS,
        ),
    )

    downloads_per_package = _download_deps(rctx, output)

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
                features = _format_inner_list(info.features, "%s"),
                build_deps = _format_inner_list(info.deps, ":%s_build"),
                lib_deps = _format_inner_list(info.deps, ":%s"),
                cpus = "1" if not package in packages else packages[package],
            )
            for package, info in depend_info.items()
        ]),
    ))

    rctx.file("vcpkg/BUILD.bazel", _VCPKG_BAZEL)

    rctx.file("vcpkg/downloads/BUILD.bazel", "\n".join([
        _PACKAGE_DOWNLOAD_TPL.format(
            package_name = package_name,
            downloads = _format_inner_list(downloads, "%s"),
        )
        for package_name, downloads in downloads_per_package.items()
    ]))
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
    if rctx.attr.release:
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

    _bootstrap(
        rctx,
        output = ".",
        packages = rctx.attr.packages,
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)

bootstrap = repository_rule(
    implementation = _bootrstrap_impl,
    attrs = {
        "release": attr.string(
            doc = "The vcpkg version, either this or commit must be specified",
        ),
        "commit": attr.string(
            doc = "The vcpkg commit, either this of version must be specified",
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
