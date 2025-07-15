load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")
load("//vcpkg/bootstrap:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap:vcpkg_exec.bzl", "exec_check", "vcpkg_exec")
load("//vcpkg/toolchain:current_toolchain.bzl", "DEFAULT_TRIPLET_SETS", "format_additions")
load(
    "//vcpkg/vcpkg_utils:format_utils.bzl",
    "add_or_extend_dict_to_list_in_dict",
    "format_inner_dict_with_value_lists",
    "format_inner_list",
)
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

def _download_vcpkg_tool(rctx, output, pu):
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

_VCPKG_WRAPPER = """\
#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname "$0")

exec "${SCRIPT_DIR}/vcpkg/vcpkg" "$@"
"""

def _initialize(rctx, output, packages, packages_ports_patches, pu):
    rctx.file(
        "vcpkg.json",
        json.encode_indent({
            "dependencies": packages,
        }),
    )

    rctx.file(
        "vcpkg_wrapper.sh",
        _VCPKG_WRAPPER,
        executable = True,
    )

    rctx.template(
        "%s/overlay_triplets/%s.cmake" % (
            output,
            pu.cmake_definitions.triplet,
        ),
        pu.triplet_template,
        substitutions = pu.cmake_definitions.substitutions | format_additions(
            {},
            DEFAULT_TRIPLET_SETS,
        ),
    )

    for patch_file, package in packages_ports_patches.items():
        patch(
            rctx,
            patches = [patch_file],
            patch_args = [
                "-d",
                "%s/vcpkg/ports/%s" % (
                    output,
                    package,
                ),
            ],
        )

_DOWNLOAD_TRY_PREFIX = "Trying to download "
_DOWNLOAD_TRY_POSTFIX = " using asset cache script"
_USING_CACHED_PREFIX = "-- Using cached "

def _extract_downloads(rctx, result, output, attempt):
    if attempt == 15:
        return "\n".join([
            "We ran 'vcpkg install --only-downloads' to collect downloads 15 times,",
            "but didn't collect all, probably we are in corrupted state",
        ])

    for buildtree in rctx.path("%s/vcpkg/buildtrees" % output).readdir():
        downloads = set()
        for buildtree_inner in buildtree.readdir():
            if buildtree_inner.basename.endswith(".log"):
                if buildtree_inner.basename.startswith("stdout"):
                    buildtree_log_content = rctx.read(buildtree_inner)
                    for line in buildtree_log_content.split("\n"):
                        if line.startswith(_DOWNLOAD_TRY_PREFIX):
                            if not line.endswith(_DOWNLOAD_TRY_POSTFIX):
                                return "Can't parse try-download line: %s" % line

                            download = line[len(_DOWNLOAD_TRY_PREFIX):-len(_DOWNLOAD_TRY_POSTFIX)].strip()
                        elif line.startswith(_USING_CACHED_PREFIX):
                            download = line[len(_USING_CACHED_PREFIX):].strip()
                        else:
                            continue

                        if download[0] == "/":
                            download = paths.basename(download)
                        downloads.add(download)

                rctx.delete(buildtree_inner)

        if buildtree.basename in result:
            result[buildtree.basename] |= downloads
        else:
            result[buildtree.basename] = downloads

    return None

def _perform_fixups(rctx, output, tmpdir, packages_repo_fixups, pu):
    for package, sh_lines in packages_repo_fixups.items():
        rctx.file(
            "%s/fixups/%s.sh" % (output, package),
            content = "\n".join([
                "#!/usr/bin/env bash",
                "set -eu",
            ] + sh_lines),
            executable = True,
        )
        rctx.execute(
            ["%s/fixups/%s.sh" % (output, package)],
            environment = {
                "PORT_DIR": "%s/vcpkg/ports/%s" % (output, package),
                "INSTALL_DIR": "%s/install/%s" % (tmpdir, pu.prefix),
            },
        )

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

def _download_deps(rctx, output, tmpdir, external_bins):
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
    for attempt in range(16):
        rctx.file("collect_assets.csv", "", executable = False)

        # Call `install --only-downloads` jsut to collect csv with urls and sha512
        _, err = vcpkg_exec(rctx, "install", install_args, output, tmpdir, external_bins)
        if err:
            return None, err

        if attempt:
            err = _extract_downloads(rctx, downloads, output, attempt)
            if err:
                return None, err

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

    exec_check(
        rctx,
        "Moving downloads",
        [
            "mv",
            "%s/downloads" % tmpdir,
            "downloads",
        ],
        workdir = output,
    )

    return downloads, None

_BUILD_BAZEL_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_build", "vcpkg_lib", "vcpkg_collect_outputs")
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

{packages}

{collect_outputs}\
"""

_VCPKG_PACKAGE_TPL = """\
vcpkg_build(
    name = "{package}_build",
    package_name = "{package}",
    port = "@vcpkg//vcpkg/ports:{package}",
    buildtree = "@vcpkg//vcpkg/buildtrees:{package}",
    downloads = "@vcpkg//downloads:{package}",
    package_features = {features},
    deps = {build_deps}, 
    cpus = "{cpus}",
)

vcpkg_lib(
    name = "{package}",
    build = ":{package}_build",
    deps = {lib_deps},
    include_postfixes = {include_postfixes},
    visibility = ["@vcpkg_{package}//:__subpackages__"],
)
"""

_VCPKG_COLLECT_OUTPUTS_TPL = """\
vcpkg_collect_outputs(
    name = "{name}",
    packages_builds = {packages_builds},
    packages_to_prefixes = {packages_to_prefixes},
    visibility = ["//visibility:public"],
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
    srcs = {downloads},
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

_BUILDTREE_BAZEL_TPL = """\
filegroup(
    name = "{package}",
    srcs = glob(
        [ "{package}/*" ],
        exclude = [
            "{package}/*-rel",
            "{package}/*-dbg",
        ],
        exclude_directories = 0,
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
"""

def _write_templates(
        rctx,
        output,
        packages_cpus,
        depend_info,
        downloads_per_package,
        pp_to_include_postfixes,
        pp_to_collect_outputs,
        pu):
    collect_outputs = {}

    def _package_tpl(package, info):
        include_postfixes = []
        for prefix, postfixes in pp_to_include_postfixes.items():
            if not package.startswith(prefix):
                continue

            include_postfixes += postfixes

        for prefix, outputs in pp_to_collect_outputs.items():
            if not package.startswith(prefix):
                continue

            for value in outputs:
                name, prefix = value.split("=")

                add_or_extend_dict_to_list_in_dict(
                    collect_outputs,
                    name,
                    {package: [prefix]},
                )

        return _VCPKG_PACKAGE_TPL.format(
            package = package,
            features = format_inner_list(info.features),
            build_deps = format_inner_list(info.deps, pattern = "\":%s_build\""),
            lib_deps = format_inner_list(info.deps, pattern = "\":%s\""),
            include_postfixes = format_inner_list(include_postfixes),
            cpus = "1" if not package in packages_cpus else packages_cpus[package],
        )

    rctx.file("%s/BUILD.bazel" % output, _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
        host_cpu_count = pu.host_cpus_count(),
        packages = "\n".join([
            _package_tpl(package, info)
            for package, info in depend_info.items()
        ]),
        collect_outputs = "\n".join([
            _VCPKG_COLLECT_OUTPUTS_TPL.format(
                name = name,
                packages_builds = format_inner_list(
                    packages_to_prefixes.keys(),
                    pattern = "\":%s_build\"",
                ),
                packages_to_prefixes = format_inner_dict_with_value_lists(
                    packages_to_prefixes,
                ),
            )
            for name, packages_to_prefixes in collect_outputs.items()
            if packages_to_prefixes
        ]),
    ))

    rctx.file("%s/vcpkg/BUILD.bazel" % output, _VCPKG_BAZEL)

    rctx.file("%s/downloads/BUILD.bazel" % output, "\n".join([
        _PACKAGE_DOWNLOAD_TPL.format(
            package_name = package_name,
            downloads = format_inner_list(
                downloads,
                pattern = "\"%s\"",
            ),
        )
        for package_name, downloads in downloads_per_package.items()
    ]))
    rctx.file("%s/vcpkg/scripts/BUILD.bazel" % output, _SCRIPTS_BAZEL)
    rctx.file("%s/vcpkg/triplets/BUILD.bazel" % output, _TRIPLETS_BAZEL)
    rctx.file("%s/vcpkg/ports/BUILD.bazel" % output, "\n".join([
        _PORT_BAZEL_TPL.format(port = port)
        for port in depend_info.keys()
    ]))
    rctx.file("%s/vcpkg/buildtrees/BUILD.bazel" % output, "\n".join([
        _BUILDTREE_BAZEL_TPL.format(package = package)
        for package in depend_info.keys()
    ]))

def _bootstrap(
        rctx,
        output,
        tmpdir,
        external_bins,
        packages,
        packages_ports_patches,
        packages_cpus,
        packages_repo_fixups,
        pp_to_include_postfixes,
        pp_to_collect_outputs):
    pu = platform_utils(rctx)

    _download_vcpkg_tool(rctx, output, pu)

    _initialize(rctx, output, packages, packages_ports_patches, pu)

    _perform_fixups(rctx, output, tmpdir, packages_repo_fixups, pu)

    downloads_per_package, err = _download_deps(rctx, output, tmpdir, external_bins)
    if err:
        return err

    depend_info, err = collect_depend_info(rctx, output, tmpdir, external_bins, packages)
    if err:
        return err

    _write_templates(
        rctx,
        output,
        packages_cpus,
        depend_info,
        downloads_per_package,
        pp_to_include_postfixes,
        pp_to_collect_outputs,
        pu,
    )

    return None

def _bootrstrap_impl(rctx):
    external_bins = paths.dirname(str(rctx.path(rctx.attr.external_bins)))

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

    tmpdir_res, err = exec_check(rctx, "mktemp", [
        "mktemp",
        "-d",
        "-t",
        "vcpkg.bootstrap.XXXXXX",
    ])

    if err:
        fail(err)

    tmpdir = tmpdir_res.stdout.strip()

    err = _bootstrap(
        rctx,
        output = ".",
        tmpdir = tmpdir,
        external_bins = external_bins,
        packages = rctx.attr.packages,
        packages_cpus = rctx.attr.packages_cpus,
        packages_repo_fixups = rctx.attr.packages_repo_fixups,
        packages_ports_patches = rctx.attr.packages_ports_patches,
        pp_to_include_postfixes = rctx.attr.pp_to_include_postfixes,
        pp_to_collect_outputs = rctx.attr.pp_to_collect_outputs,
    )

    rctx.delete(tmpdir)

    if err:
        fail(err)

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
        "packages": attr.string_list(
            mandatory = True,
            doc = "Packages to install",
        ),
        "packages_cpus": attr.string_dict(
            mandatory = False,
            doc = "Packages build assigned cpu count",
        ),
        "packages_repo_fixups": attr.string_list_dict(
            mandatory = False,
            doc = "Packages fixup bash script lines",
        ),
        "packages_ports_patches": attr.label_keyed_string_dict(
            mandatory = False,
            doc = "Patches to apply to port directory",
        ),
        "pp_to_include_postfixes": attr.string_list_dict(
            mandatory = False,
            doc = "Postfixes to add to includes keyed by package prefixes.",
        ),
        "pp_to_collect_outputs": attr.string_list_dict(
            mandatory = False,
            doc = "Directories prefix in outputs to add collect.",
        ),
        "sha256": attr.string(
            mandatory = False,
            doc = "SHA256 sum of release archive",
        ),
        "external_bins": attr.label(
            mandatory = True,
        ),
    },
)
