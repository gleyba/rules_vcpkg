VcpkgPackageInfo = provider(
    fields = [
        "name",
        "port",
        "buildtree",
    ],
)

VcpkgPackageDepsInfo = provider(
    fields = [
        "deps",
    ],
)

def _vcpkg_build_impl(ctx):
    vcpkg_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"].vcpkg_info

    # TODO: Invent something
    return [
        VcpkgPackageInfo(
            name = ctx.attr.name,
            port = ctx.files.port,
            buildtree = ctx.files.buildtree,
        ),
        VcpkgPackageDepsInfo(
            deps = depset(transitive = [
                dep[VcpkgPackageDepsInfo].deps
                for dep in ctx.attr.deps
            ]),
        ),
    ]

vcpkg_build = rule(
    implementation = _vcpkg_build_impl,
    attrs = {
        "port": attr.label(allow_files = True),
        "buildtree": attr.label(allow_files = True),
        "deps": attr.label_list(providers = [
            VcpkgPackageInfo,
            VcpkgPackageDepsInfo,
        ]),
    },
    toolchains = [
        "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
    ],
)

_BAZEL_PACKAGE_TPL = """\
alias(
    name = "{package}",
    actual = "@vckp//:{package}",
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
