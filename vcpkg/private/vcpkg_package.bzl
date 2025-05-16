load("@rules_cc//cc:defs.bzl", "CcInfo")

def _vcpkg_lib_link_transition_impl(settings, attr):
    _ignore = (settings, attr)
    return {
        "//command_line_option:compilation_mode": "fastbuild",
    }

# Call to `vcpkg build` produce both debug and release artifacts.
# Lets use this transition hack to not to break cacheability
# when `-c opt` or `-c dbg` command line options are used.
# Our transition will override the compilation mode to fastbuild,
# and have same output paths.
vcpkg_lib_link_transition = transition(
    implementation = _vcpkg_lib_link_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ],
)

def _vcpkg_lib_link_impl(ctx):
    return ctx.attr.lib[0][CcInfo]

_vcpkg_lib_link = rule(
    implementation = _vcpkg_lib_link_impl,
    attrs = {
        "lib": attr.label(
            mandatory = True,
            providers = [CcInfo],
            cfg = vcpkg_lib_link_transition,
            doc = "Lib to link",
        ),
    },
)

def vcpkg_lib_link(name, release_lib, debug_lib, **kwargs):
    _vcpkg_lib_link(
        name = name,
        lib = select({
            "@rules_vcpkg//vcpkg/vcpkg_utils:is_release_build": release_lib,
            "//conditions:default": debug_lib,
        }),
        **kwargs
    )

_BAZEL_PACKAGE_TPL = """\
load("@rules_vcpkg//vcpkg/private:vcpkg_package.bzl", "vcpkg_lib_link")

vcpkg_lib_link(
    name = "{package}",
    release_lib = "@vcpkg//:{package}_release",
    debug_lib = "@vcpkg//:{package}_debug",
    visibility = ["//visibility:public"],
)
"""

def _vcpkg_package_impl(rctx):
    rctx.file(
        "BUILD.bazel",
        _BAZEL_PACKAGE_TPL.format(
            package = rctx.attr.package,
        ),
    )

vcpkg_package = repository_rule(
    implementation = _vcpkg_package_impl,
    attrs = {
        "package": attr.string(doc = "Package name"),
    },
)
