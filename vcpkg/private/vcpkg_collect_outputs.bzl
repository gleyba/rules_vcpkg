load("//vcpkg/private:vcpkg_build.bzl", "VcpkgBuiltPackageInfo")

def _vcpkg_collect_outputs_impl(ctx):
    output = ctx.actions.declare_directory(ctx.attr.name)

    args = ctx.actions.args()
    args.add(output.path)

    inputs = []

    for pb in ctx.attr.packages_builds:
        package = pb[VcpkgBuiltPackageInfo].name
        package_output = pb[VcpkgBuiltPackageInfo].output
        inputs.append(package_output)

        if package not in ctx.attr.packages_to_prefixes:
            continue

        for prefix in ctx.attr.packages_to_prefixes[package]:
            args.add("%s/%s" % (
                package_output.path,
                prefix,
            ))

    ctx.actions.run(
        outputs = [output],
        inputs = inputs,
        arguments = [args],
        executable = ctx.executable._collect_outputs_by_prefixes,
    )

    return DefaultInfo(files = depset([output]))

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
        "_collect_outputs_by_prefixes": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:collect_outputs_by_prefixes",
            executable = True,
            cfg = "exec",
            doc = "Tool to collect outputs with prefixes",
        ),
    },
)
