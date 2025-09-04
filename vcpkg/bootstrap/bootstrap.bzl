load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")
load("//vcpkg/bootstrap/utils:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/bootstrap/utils:download_deps.bzl", "download_deps")
load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "format_additions", "format_inner_dict", "format_inner_list")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:logging.bzl", "L")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

def _download_vcpkg_tool(rctx, bootstrap_ctx):
    rctx.report_progress("Downloading VCPKG tool")

    tool_meta = {
        line.split("=")[0]: line.split("=")[1]
        for line in rctx.read("%s/vcpkg/scripts/vcpkg-tool-metadata.txt" % bootstrap_ctx.output).split("\n")
        if line
    }

    rctx.download(
        url = bootstrap_ctx.pu.downloads.url_tpl % tool_meta["VCPKG_TOOL_RELEASE_TAG"],
        output = "%s/vcpkg/vcpkg" % bootstrap_ctx.output,
        integrity = "sha512-%s" % base64_encode_hexstr(tool_meta[bootstrap_ctx.pu.downloads.sha_key]),
        executable = True,
    )

_VCPKG_WRAPPER = """\
#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname "$0")

exec "${SCRIPT_DIR}/vcpkg/vcpkg" "$@"
"""

def _initialize(rctx, bootstrap_ctx):
    rctx.report_progress("Initializing VCPKG and pactching ports")
    rctx.file(
        "vcpkg.json",
        json.encode_indent({
            "dependencies": bootstrap_ctx.packages,
        }),
    )

    rctx.file(
        "vcpkg_wrapper.sh",
        _VCPKG_WRAPPER,
        executable = True,
    )

    rctx.template(
        "%s/overlay_triplets/%s.cmake" % (
            bootstrap_ctx.output,
            bootstrap_ctx.pu.definitions.triplet,
        ),
        bootstrap_ctx.pu.triplet_template,
        substitutions = bootstrap_ctx.pu.definitions.substitutions | format_additions(
            {},
            bootstrap_ctx.config_settings,
        ),
    )

    for patch_file, package in bootstrap_ctx.packages_ports_patches.items():
        patch(
            rctx,
            patches = [patch_file],
            patch_args = [
                "-d",
                "%s/vcpkg/ports/%s" % (
                    bootstrap_ctx.output,
                    package,
                ),
            ],
        )
        rctx.watch(patch_file)

def _list_to_pairs(items):
    return [
        (items[i], items[i + 1])
        for i in range(0, len(items), 2)
    ]

def _perform_install_fixups(rctx, bootstrap_ctx):
    rctx.report_progress("Initializing VCPKG and pactching ports")

    for file, replaces in bootstrap_ctx.vcpkg_distro_fixup_replace.items():
        to_check_path = rctx.path("%s/vcpkg/%s" % (bootstrap_ctx.output, file))
        if not to_check_path.exists:
            L.warn("Can't find '%s' file in VCPKG distro" % file)

        data = rctx.read(to_check_path)
        for pattern, replace in _list_to_pairs(replaces):
            data = data.replace(pattern, replace)

        rctx.delete(to_check_path)
        rctx.file(to_check_path, data)

    for package, sh_lines in bootstrap_ctx.packages_install_fixups.items():
        rctx.file(
            "%s/install_fixups/%s.sh" % (bootstrap_ctx.output, package),
            content = "\n".join([
                "#!/usr/bin/env bash",
                "set -eu",
            ] + sh_lines),
            executable = True,
        )
        rctx.execute(
            ["%s/install_fixups/%s.sh" % (bootstrap_ctx.output, package)],
            environment = {
                "PORT_DIR": "%s/vcpkg/ports/%s" % (bootstrap_ctx.output, package),
                "INSTALL_DIR": "%s/install/%s" % (
                    bootstrap_ctx.tmpdir,
                    bootstrap_ctx.pu.prefix,
                ),
            },
        )

def _perform_buildtree_fixups(rctx, bootstrap_ctx):
    rctx.report_progress("Performing VCPKG buildtrees fixups")

    for package, sh_lines in bootstrap_ctx.packages_buildtree_fixups.items():
        rctx.file(
            "%s/buildtree_fixups/%s.sh" % (bootstrap_ctx.output, package),
            content = "\n".join([
                "#!/usr/bin/env bash",
                "set -eu",
            ] + sh_lines),
            executable = True,
        )
        rctx.execute(
            ["%s/buildtree_fixups/%s.sh" % (bootstrap_ctx.output, package)],
            environment = {
                "BUILDTREE_DIR": "%s/vcpkg/buildtrees/%s" % (bootstrap_ctx.output, package),
            },
        )

    for patch_file, package in bootstrap_ctx.packages_src_patches.items():
        src_dir = rctx.path("%s/vcpkg/buildtrees/%s/src" % (
            bootstrap_ctx.output,
            package,
        ))

        if not src_dir.exists:
            return "There is no src dir in 'vcpkg/buildtrees/%s', but patch requested" % package

        if not src_dir.is_dir:
            return "'vcpkg/buildtrees/%s' is not a directory, but patch requested" % package

        clean_dir = None
        for inner in src_dir.readdir():
            if inner.basename.endswith(".clean"):
                clean_dir = inner
                break

        if not clean_dir or not clean_dir.is_dir:
            return "'vcpkg/buildtrees/%s' contains not '.clean' postfixed subdirectory, but patch requested" % package

        patch(
            rctx,
            patches = [patch_file],
            patch_args = [
                "-d",
                clean_dir,
            ],
        )
        rctx.watch(patch_file)

    return None

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

def _write_templates(rctx, bootstrap_ctx, depend_info, downloads_per_package):
    rctx.report_progress("Writing VCPKG templates")

    rctx.file("%s/BUILD.bazel" % bootstrap_ctx.output, _BUILD_BAZEL_TPL.format(
        os = bootstrap_ctx.pu.targets.os,
        arch = bootstrap_ctx.pu.targets.arch,
        config_settings = format_inner_dict(bootstrap_ctx.config_settings),
    ))

    rctx.file("%s/vcpkg/BUILD.bazel" % bootstrap_ctx.output, _VCPKG_BAZEL)

    rctx.file("%s/downloads/BUILD.bazel" % bootstrap_ctx.output, "\n".join([
        _PACKAGE_DOWNLOAD_TPL.format(
            package_name = package_name,
            downloads = format_inner_list(
                downloads,
                pattern = "\"{dep}\"",
            ),
        )
        for package_name, downloads in downloads_per_package.items()
    ]))
    rctx.file("%s/vcpkg/scripts/BUILD.bazel" % bootstrap_ctx.output, _SCRIPTS_BAZEL)
    rctx.file("%s/vcpkg/triplets/BUILD.bazel" % bootstrap_ctx.output, _TRIPLETS_BAZEL)
    rctx.file("%s/vcpkg/ports/BUILD.bazel" % bootstrap_ctx.output, "\n".join([
        """load("@bazel_skylib//rules/directory:directory.bzl", "directory")""",
        "",
    ] + [
        _PORT_BAZEL_TPL.format(port = port)
        for port in depend_info.keys()
    ]))
    rctx.file("%s/vcpkg/buildtrees/BUILD.bazel" % bootstrap_ctx.output, "\n".join([
        _BUILDTREE_BAZEL_TPL.format(package = package)
        for package in depend_info.keys()
    ]))

def _bootstrap(rctx, bootstrap_ctx):
    _download_vcpkg_tool(rctx, bootstrap_ctx)

    _initialize(rctx, bootstrap_ctx)

    _perform_install_fixups(rctx, bootstrap_ctx)

    depend_info, err = collect_depend_info(rctx, bootstrap_ctx)
    if err:
        return err

    downloads_per_package, err = download_deps(rctx, bootstrap_ctx, depend_info)
    if err:
        return err

    err = _perform_buildtree_fixups(rctx, bootstrap_ctx)
    if err:
        return err

    _write_templates(rctx, bootstrap_ctx, depend_info, downloads_per_package)

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
        rctx = rctx,
        bootstrap_ctx = struct(
            pu = platform_utils(rctx),
            output = ".",
            tmpdir = tmpdir,
            external_bins = external_bins,
            packages = rctx.attr.packages,
            packages_install_fixups = rctx.attr.packages_install_fixups,
            packages_buildtree_fixups = rctx.attr.packages_buildtree_fixups,
            packages_ports_patches = rctx.attr.packages_ports_patches,
            packages_src_patches = rctx.attr.packages_src_patches,
            vcpkg_distro_fixup_replace = rctx.attr.vcpkg_distro_fixup_replace,
            verbose = rctx.attr.verbose,
            config_settings = rctx.attr.config_settings,
        ),
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
        "packages_src_patches": attr.label_keyed_string_dict(
            mandatory = False,
            doc = "Patches to apply to src directory",
        ),
        "config_settings": attr.string_dict(
            doc = "Vcpkg triplet configuration settings",
            mandatory = True,
        ),
        "vcpkg_distro_fixup_replace": attr.string_list_dict(
            mandatory = False,
            doc = "Key is file path and value - list of sequential pairs of values, pattern to search and relace to",
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
