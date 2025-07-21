load("@rules_cc//cc:defs.bzl", "cc_import", "cc_library")
load("//vcpkg/private:vcpkg_build.bzl", "VcpkgBuiltPackageInfo")

def _extract_package_outputs_impl(ctx):
    package_info = ctx.attr.build[VcpkgBuiltPackageInfo]
    output_dir = ctx.actions.declare_directory(ctx.attr.name)

    args = ctx.actions.args()
    args.add(package_info.output.path)
    args.add(output_dir.path)
    args.add(ctx.attr.dir_prefix)
    args.add(ctx.attr.collect_type)
    args.add_all(ctx.files.additional)

    ctx.actions.run(
        tools = [
            ctx.executable._extract_package_outputs,
        ],
        inputs = [
            package_info.output,
        ] + ctx.files.additional,
        outputs = [
            output_dir,
        ],
        executable = ctx.executable._extract_package_outputs,
        arguments = [args],
    )

    return DefaultInfo(files = depset([output_dir]))

_extract_package_outputs = rule(
    implementation = _extract_package_outputs_impl,
    attrs = {
        "build": attr.label(
            mandatory = True,
            providers = [VcpkgBuiltPackageInfo],
            doc = "Target of vcpkg_build rule",
        ),
        "dir_prefix": attr.string(
            mandatory = True,
            doc = "Directory prefix to search files in",
        ),
        "collect_type": attr.string(
            mandatory = True,
            doc = "Files extension to search for",
        ),
        "additional": attr.label_list(
            mandatory = False,
            allow_files = True,
            doc = "Additional files to copy to output",
        ),
        "_extract_package_outputs": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:extract_package_outputs",
            executable = True,
            cfg = "exec",
            doc = "Tool to prepare vcpkg install directory structure",
        ),
    },
)

def vcpkg_lib(
        package,
        build,
        deps,
        include_postfixes,
        info_header,
        info_source,
        **kwargs):
    cc_library(
        name = "vcpkg_%s_info" % package,
        hdrs = [info_header],
        srcs = [info_source],
        linkstatic = True,
    )
    _extract_package_outputs(
        name = "include",
        build = build,
        dir_prefix = "include",
        collect_type = "any",
    )
    _extract_package_outputs(
        name = "release_lib",
        build = build,
        dir_prefix = "lib",
        collect_type = "libs",
        additional = [":vcpkg_%s_info" % package],
    )
    cc_import(
        name = "release_import",
        hdrs = [":include"],
        objects = [":release_lib"],
    )
    cc_library(
        name = "release",
        deps = [":release_import"] + [
            "//%s/libs:release" % dep
            for dep in deps
        ],
        includes = ["include"] + [
            "include/%s" % postfix
            for postfix in include_postfixes
        ],
        **kwargs
    )
    _extract_package_outputs(
        name = "debug_lib",
        build = build,
        dir_prefix = "debug/lib",
        collect_type = "libs",
        additional = [":vcpkg_%s_info" % package],
    )
    cc_import(
        name = "debug_import",
        hdrs = [":include"],
        objects = [":debug_lib"],
    )
    cc_library(
        name = "debug",
        deps = [":debug_import"] + [
            "//%s/libs:debug" % dep
            for dep in deps
        ],
        includes = ["include"] + [
            "include/%s" % postfix
            for postfix in include_postfixes
        ],
        **kwargs
    )
