load("@rules_pkg//pkg:providers.bzl", "PackageFilesInfo")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "add_or_extend_list_in_dict", "format_inner_list")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_VCPKG_BUILD_BZL_TPL = """\
load("@rules_vcpkg//vcpkg/private:vcpkg_build.bzl", "vcpkg_build", "unwrap_cpus_count")

_CPU_COUNT = unwrap_cpus_count("{cpus}", {host_cpus})

_EXEC_REQS = {{
    "cpu:%s" % _CPU_COUNT: "",
    "resources:cpu:%s" % _CPU_COUNT: "",
}}

def _num_cpus(_os, _num_inputs):
    return {{"cpu": int(_CPU_COUNT)}}

{package_escaped}_build = vcpkg_build(_CPU_COUNT, _num_cpus, _EXEC_REQS)
"""

_VCPKG_BUILD_TPL = """\
load(":{package_escaped}_build.bzl", "{package_escaped}_build")

{package_escaped}_build(
    name = "vcpkg_build",
    package_name = "{package}",
    port = "@{bootstrap_repo}//vcpkg/ports:{package}",
    buildtree = "@{bootstrap_repo}//vcpkg/buildtrees:{package}",
    downloads = "@{bootstrap_repo}//downloads:{package}",
    assets = "@{bootstrap_repo}//assets/{package}",
    package_features = {features},
    deps = {build_deps}, 
    cflags = {cflags},
    override_sources = {override_sources},
    overlay_sources = {overlay_sources},
    linkerflags = {linkerflags},
    visibility = ["//visibility:public"],
)
"""

_VCPKG_LIB_HEADER_TPL = """\
const char* {package_as_fn}_info();
"""

_VCPKG_LIB_SOURCE_TPL = """\
#include "vcpkg_{package}_info.h"

const char* {package_as_fn}_info() {{
    return "{package}";
}}
"""

_VCPKG_LIB_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_lib")

vcpkg_lib(
    package = "{package}",
    build = "//{package}/vcpkg_build",
    deps = {lib_deps},
    info_header = "vcpkg_{package}_info.h",
    info_source = "vcpkg_{package}_info.c",
    include_postfixes = {include_postfixes},
    visibility = ["//:__subpackages__"],
)
"""

_BAZEL_PACKAGE_TPL = """\
load("@rules_vcpkg//vcpkg/private:vcpkg_package.bzl", "vcpkg_package")

vcpkg_package(
    name = "{package}",
    release_lib = "//{package}/libs:release",
    debug_lib = "//{package}/libs:debug",
    visibility = ["//visibility:public"],
)
"""

def _declare_impl(rctx):
    pu = platform_utils(rctx)
    host_cpu_count = pu.host_cpus_count()

    depend_info = json.decode(rctx.read(rctx.path(rctx.attr.depend_info)))

    packages_overlay_sources = {}
    for overlay_src, package in rctx.attr.packages_overlay_sources.items():
        add_or_extend_list_in_dict(packages_overlay_sources, package, [overlay_src])

    for package, info in depend_info.items():
        include_postfixes = []
        for prefix, postfixes in rctx.attr.pp_to_include_postfixes.items():
            if not package.startswith(prefix):
                continue

            include_postfixes += postfixes

        package_escaped = package.replace("-", "_")

        rctx.file(
            "%s/vcpkg_build/%s_build.bzl" % (
                package,
                package_escaped,
            ),
            _VCPKG_BUILD_BZL_TPL.format(
                package = package,
                package_escaped = package_escaped,
                cpus = "1" if not package in rctx.attr.packages_cpus else rctx.attr.packages_cpus[package],
                host_cpus = host_cpu_count,
            ),
        )

        override_sources = "None"
        if package in rctx.attr.packages_override_sources:
            override_sources = '"%s"' % rctx.attr.packages_override_sources[package]

        rctx.file(
            "%s/vcpkg_build/BUILD.bazel" % package,
            _VCPKG_BUILD_TPL.format(
                package = package,
                package_escaped = package_escaped,
                bootstrap_repo = rctx.attr.bootstrap_repo,
                features = format_inner_list(info["features"]),
                build_deps = format_inner_list(info["deps"], pattern = "\"//{dep}/vcpkg_build\""),
                cflags = format_inner_list(rctx.attr.packages_cflags.get(package, [])),
                linkerflags = format_inner_list(rctx.attr.packages_linkerflags.get(package, [])),
                override_sources = override_sources,
                overlay_sources = format_inner_list(packages_overlay_sources.get(package, [])),
            ),
        )

        package_as_fn = package.replace("-", "_")

        rctx.file(
            "{package}/libs/vcpkg_{package}_info.h".format(package = package),
            _VCPKG_LIB_HEADER_TPL.format(package_as_fn = package_as_fn),
        )

        rctx.file(
            "{package}/libs/vcpkg_{package}_info.c".format(package = package),
            _VCPKG_LIB_SOURCE_TPL.format(
                package = package,
                package_as_fn = package_as_fn,
            ),
        )

        rctx.file(
            "%s/libs/BUILD.bazel" % package,
            _VCPKG_LIB_TPL.format(
                package = package,
                lib_deps = format_inner_list(info["deps"]),
                include_postfixes = format_inner_list(include_postfixes),
                visibility = "//visibility:public" if package in rctx.attr.packages else "//:__subpackages__",
            ),
        )

        depend_info[package]["vcpkg_build"] = "@%s//%s/vcpkg_build" % (
            rctx.original_name,
            package,
        )

    for package in rctx.attr.packages:
        rctx.file(
            "%s/BUILD.bazel" % package,
            _BAZEL_PACKAGE_TPL.format(
                package = package,
            ),
        )

    rctx.file("BUILD.bazel", "")

    rctx.file(
        "packages_info.bzl",
        "PACKAGES_INFO = %s" % json.encode_indent(depend_info),
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    else:
        return None

declare = repository_rule(
    implementation = _declare_impl,
    attrs = {
        "bootstrap_repo": attr.string(
            mandatory = True,
            doc = "Repository name with vcpkg bootstrap",
        ),
        "depend_info": attr.label(
            mandatory = True,
            doc = "File with packages information, features and dependency graph",
        ),
        "packages": attr.string_list(
            mandatory = True,
            doc = "Packages to install",
        ),
        "packages_cpus": attr.string_dict(
            mandatory = False,
            doc = "Packages build assigned cpu count",
        ),
        "packages_cflags": attr.string_list_dict(
            mandatory = False,
            doc = "Additional c flags to propagate to build, are not transitive",
        ),
        "packages_linkerflags": attr.string_list_dict(
            mandatory = False,
            doc = "Additional linker flags to propagate to build, are not transitive",
        ),
        "packages_override_sources": attr.string_dict(
            mandatory = False,
            doc = "Override sources location for packages, useful for debug",
        ),
        "packages_overlay_sources": attr.label_keyed_string_dict(
            mandatory = False,
            providers = [PackageFilesInfo],
            doc = "Overlay sources to add to package srcs, created with `pkg_files`",
        ),
        "pp_to_include_postfixes": attr.string_list_dict(
            mandatory = False,
            doc = "Postfixes to add to includes keyed by package prefixes.",
        ),
    },
)
