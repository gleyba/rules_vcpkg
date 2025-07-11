load("//vcpkg/private:vcpkg_build.bzl", "VcpkgBuiltPackageInfo")

def _vcpkg_collect_outputs_impl(ctx):
    return []

vcpkg_collect_outputs = rule(
    implementation = _vcpkg_collect_outputs_impl,
    attrs = {
        "packages_builds": attr.label_list(
            mandatory = True,
            providers = [VcpkgBuiltPackageInfo],
            doc = "Targets of vcpkg_build rule",
        ),
        "packages_to_prefixes": attr.string_list_dict(
            mandatory = True,
            doc = "Map of package to prefixes list to collect",
        ),
    },
)
