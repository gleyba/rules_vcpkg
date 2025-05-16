def _vcpkg_package_link_transition_impl(settings, attr):
    _ignore = (settings, attr)
    return {
        "//command_line_option:compilation_mode": "fastbuild",
    }

vcpkg_package_link_transition = transition(
    implementation = _vcpkg_package_link_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ],
)

def _vcpkg_package_link_impl(ctx):
    package = ctx.attr.package[0]

    # print(package[VcpkgPackageInfo].output_dir.path)
    # print(package[VcpkgPackageInfo].output_dir.is_directory)
    return package[DefaultInfo]

vcpkg_package_link = rule(
    implementation = _vcpkg_package_link_impl,
    attrs = {
        "package": attr.label(
            mandatory = True,
            # Call to `vcpkg build` produce both debug and release artifacts.
            # Lets use this transition hack to not to break cacheability
            # when `-c opt` or `-c dbg` command line options are used.
            # Our transition will override the compilation mode to fastbuild,
            # and have same output paths.
            cfg = vcpkg_package_link_transition,
            doc = "Package to link",
        ),
    },
)

_BAZEL_PACKAGE_TPL = """\
load("@rules_vcpkg//vcpkg/private:vcpkg_package.bzl", "vcpkg_package_link")

vcpkg_package_link(
    name = "{package}",
    package = "@vcpkg//:{package}",
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
