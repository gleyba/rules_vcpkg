load("//vcpkg/vcpkg_utils:format_utils.bzl", "format_inner_list")

_VCPKG_BUILD_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_build")

vcpkg_build(
    name = "vcpkg_build",
    package_name = "{package}",
    port = "@{bootstrap_repo}//vcpkg/ports:{package}",
    buildtree = "@{bootstrap_repo}//vcpkg/buildtrees:{package}",
    downloads = "@{bootstrap_repo}//downloads:{package}",
    assets = "@{bootstrap_repo}//assets/{package}",
    package_features = {features},
    deps = {build_deps}, 
    cpus = "{cpus}",
    visibility = ["//visibility:public"],
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

def _declare_impl(rctx):
    depend_info = json.decode(rctx.read(rctx.path(rctx.attr.depend_info)))

    for package, info in depend_info.items():
        include_postfixes = []
        for prefix, postfixes in rctx.attr.pp_to_include_postfixes.items():
            if not package.startswith(prefix):
                continue

            include_postfixes += postfixes

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
        "pp_to_include_postfixes": attr.string_list_dict(
            mandatory = False,
            doc = "Postfixes to add to includes keyed by package prefixes.",
        ),
    },
)
