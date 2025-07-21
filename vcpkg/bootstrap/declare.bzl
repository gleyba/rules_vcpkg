load(
    "//vcpkg/vcpkg_utils:format_utils.bzl",
    "add_or_extend_dict_to_list_in_dict",
    "format_inner_dict_with_value_lists",
    "format_inner_list",
)

_VCPKG_BUILD_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_build")

vcpkg_build(
    name = "vcpkg_build",
    package_name = "{package}",
    port = "@{bootstrap_repo}//vcpkg/ports:{package}",
    buildtree = "@{bootstrap_repo}//vcpkg/buildtrees:{package}",
    downloads = "@{bootstrap_repo}//downloads:{package}",
    package_features = {features},
    deps = {build_deps}, 
    cpus = "{cpus}",
    visibility = ["//:__subpackages__"],
)
"""

_VCPKG_LIB_HEADER_TPL = """\
#include <string>

namespace rules_vcpkg {{
    std::string {package_as_fn}_info();
}}
"""

_VCPKG_LIB_SOURCE_TPL = """\
#include <string>

#include "vcpkg_{package}_info.hpp"

namespace rules_vcpkg {{
    std::string {package_as_fn}_info() {{
        return "{package}";
    }}
}}
"""

_VCPKG_LIB_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_lib")

vcpkg_lib(
    package = "{package}",
    build = "//{package}/vcpkg_build",
    deps = {lib_deps},
    info_header = "vcpkg_{package}_info.hpp",
    info_source = "vcpkg_{package}_info.cpp",
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

_VCPKG_COLLECT_OUTPUTS_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_collect_outputs")

vcpkg_collect_outputs(
    name = "{name}",
    packages_builds = {packages_builds},
    packages_to_prefixes = {packages_to_prefixes},
    visibility = ["//visibility:public"],
)
"""

def _declare_impl(rctx):
    depend_info = json.decode(rctx.read(rctx.path(rctx.attr.depend_info)))

    collect_outputs = {}

    for package, info in depend_info.items():
        include_postfixes = []
        for prefix, postfixes in rctx.attr.pp_to_include_postfixes.items():
            if not package.startswith(prefix):
                continue

            include_postfixes += postfixes

        for prefix, outputs in rctx.attr.pp_to_collect_outputs.items():
            if not package.startswith(prefix):
                continue

            for value in outputs:
                name, prefix = value.split("=")

                add_or_extend_dict_to_list_in_dict(
                    collect_outputs,
                    name,
                    {package: [prefix]},
                )

        rctx.file(
            "%s/vcpkg_build/BUILD.bazel" % package,
            _VCPKG_BUILD_TPL.format(
                package = package,
                bootstrap_repo = rctx.attr.bootstrap_repo,
                features = format_inner_list(info["features"]),
                build_deps = format_inner_list(info["deps"], pattern = "\"//{dep}/vcpkg_build\""),
                cpus = "1" if not package in rctx.attr.packages_cpus else rctx.attr.packages_cpus[package],
            ),
        )

        package_as_fn = package.replace("-", "_")

        rctx.file(
            "{package}/libs/vcpkg_{package}_info.hpp".format(package = package),
            _VCPKG_LIB_HEADER_TPL.format(package_as_fn = package_as_fn),
        )

        rctx.file(
            "{package}/libs/vcpkg_{package}_info.cpp".format(package = package),
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

    for package in rctx.attr.packages:
        rctx.file(
            "%s/BUILD.bazel" % package,
            _BAZEL_PACKAGE_TPL.format(
                package = package,
            ),
        )

    # rctx.file("BUILD.bazel", _BUILD_BAZEL_TPL.format(
    #     packages = "\n".join([
    #         _package_tpl(package, info)
    #         for package, info in depend_info.items()
    #     ]),
    #     collect_outputs = "\n".join([
    #         _VCPKG_COLLECT_OUTPUTS_TPL.format(
    #             name = name,
    #             packages_builds = format_inner_list(
    #                 packages_to_prefixes.keys(),
    #                 pattern = "\":%s_build\"",
    #             ),
    #             packages_to_prefixes = format_inner_dict_with_value_lists(
    #                 packages_to_prefixes,
    #             ),
    #         )
    #         for name, packages_to_prefixes in collect_outputs.items()
    #         if packages_to_prefixes
    #     ]),
    # ))

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
        "pp_to_include_postfixes": attr.string_list_dict(
            mandatory = False,
            doc = "Postfixes to add to includes keyed by package prefixes.",
        ),
        "pp_to_collect_outputs": attr.string_list_dict(
            mandatory = False,
            doc = "Directories prefix in outputs to add collect.",
        ),
        "pp_to_collect_outputs_fexts": attr.string_list_dict(
            mandatory = False,
            doc = "Additional filtering by file extensions to `collect_outputs`.",
        ),
    },
)
