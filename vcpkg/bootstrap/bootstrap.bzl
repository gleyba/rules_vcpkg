load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")
load("//vcpkg/bootstrap/utils:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap/utils:download_deps.bzl", "download_deps")
load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/toolchain:current_toolchain.bzl", "DEFAULT_TRIPLET_SETS", "format_additions")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "format_inner_list")
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

def _perform_install_fixups(rctx, output, tmpdir, install_fixups, pu):
    for package, sh_lines in install_fixups.items():
        rctx.file(
            "%s/install_fixups/%s.sh" % (output, package),
            content = "\n".join([
                "#!/usr/bin/env bash",
                "set -eu",
            ] + sh_lines),
            executable = True,
        )
        rctx.execute(
            ["%s/install_fixups/%s.sh" % (output, package)],
            environment = {
                "PORT_DIR": "%s/vcpkg/ports/%s" % (output, package),
                "INSTALL_DIR": "%s/install/%s" % (tmpdir, pu.prefix),
            },
        )

def _perform_buildtree_fixups(rctx, output, buildtree_fixups):
    for package, sh_lines in buildtree_fixups.items():
        rctx.file(
            "%s/buildtree_fixups/%s.sh" % (output, package),
            content = "\n".join([
                "#!/usr/bin/env bash",
                "set -eu",
            ] + sh_lines),
            executable = True,
        )
        rctx.execute(
            ["%s/buildtree_fixups/%s.sh" % (output, package)],
            environment = {
                "BUILDTREE_DIR": "%s/vcpkg/buildtrees/%s" % (output, package),
            },
        )

_BUILD_BAZEL_TPL = """\
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
directory(
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
        depend_info,
        downloads_per_package,
        pu):
    rctx.file("%s/BUILD.bazel" % output, _BUILD_BAZEL_TPL.format(
        os = pu.targets.os,
        arch = pu.targets.arch,
        host_cpu_count = pu.host_cpus_count(),
    ))

    rctx.file("%s/vcpkg/BUILD.bazel" % output, _VCPKG_BAZEL)

    rctx.file("%s/downloads/BUILD.bazel" % output, "\n".join([
        _PACKAGE_DOWNLOAD_TPL.format(
            package_name = package_name,
            downloads = format_inner_list(
                downloads,
                pattern = "\"{dep}\"",
            ),
        )
        for package_name, downloads in downloads_per_package.items()
    ]))
    rctx.file("%s/vcpkg/scripts/BUILD.bazel" % output, _SCRIPTS_BAZEL)
    rctx.file("%s/vcpkg/triplets/BUILD.bazel" % output, _TRIPLETS_BAZEL)
    rctx.file("%s/vcpkg/ports/BUILD.bazel" % output, "\n".join([
        """load("@bazel_skylib//rules/directory:directory.bzl", "directory")""",
    ] + [
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
        packages_install_fixups,
        packages_buildtree_fixups,
        packages_ports_patches,
        verbose):
    pu = platform_utils(rctx)

    _download_vcpkg_tool(rctx, output, pu)

    _initialize(rctx, output, packages, packages_ports_patches, pu)

    _perform_install_fixups(rctx, output, tmpdir, packages_install_fixups, pu)

    depend_info, err = collect_depend_info(rctx, output, tmpdir, external_bins, packages)
    if err:
        return err

    downloads_per_package, err = download_deps(rctx, output, tmpdir, depend_info, external_bins, verbose)
    if err:
        return err

    _perform_buildtree_fixups(rctx, output, packages_buildtree_fixups)

    _write_templates(
        rctx,
        output,
        depend_info,
        downloads_per_package,
        pu,
    )

    rctx.file(
        "depend_info.json",
        json.encode_indent(depend_info),
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
        packages_install_fixups = rctx.attr.packages_install_fixups,
        packages_buildtree_fixups = rctx.attr.packages_buildtree_fixups,
        packages_ports_patches = rctx.attr.packages_ports_patches,
        verbose = rctx.attr.verbose,
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
        "packages_install_fixups": attr.string_list_dict(
            mandatory = False,
            doc = "Packages install dir fixup bash script lines",
        ),
        "packages_buildtree_fixups": attr.string_list_dict(
            mandatory = False,
            doc = "Packages buildtree fixup bash script lines",
        ),
        "packages_ports_patches": attr.label_keyed_string_dict(
            mandatory = False,
            doc = "Patches to apply to port directory",
        ),
        "sha256": attr.string(
            mandatory = False,
            doc = "SHA256 sum of release archive",
        ),
        "external_bins": attr.label(
            mandatory = True,
        ),
        "verbose": attr.bool(
            default = False,
            doc = "If to print debug info",
        ),
    },
)
