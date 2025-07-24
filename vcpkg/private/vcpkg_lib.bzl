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

def _vcpkg_lib_impl(
        name,
        build,
        dir_prefix,
        additional_obj_files,
        **kwargs):
    _extract_package_outputs(
        name = "%s.lib" % name,
        build = build,
        dir_prefix = dir_prefix,
        collect_type = "libs",
        additional = additional_obj_files,
    )

    cc_import(
        name = "%s.import" % name,
        hdrs = [":include"],
        objects = [":%s.lib" % name],
    )

    cc_library(
        name = name,
        deps = kwargs.pop("deps", []) + [":%s.import" % name],
        **kwargs
    )

_vcpkg_lib = macro(
    implementation = _vcpkg_lib_impl,
    inherit_attrs = native.cc_library,
    attrs = {
        "build": attr.label(
            mandatory = True,
            doc = "Target of `vcpk_build` rule with package outputs",
        ),
        "dir_prefix": attr.string(
            mandatory = True,
            doc = "Directory prefix to search files in",
        ),
        "additional_obj_files": attr.label_list(
            allow_files = True,
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
        visibility = ["//visibility:public"],
    )

    _extract_package_outputs(
        name = "include",
        build = build,
        dir_prefix = "include",
        collect_type = "any",
        visibility = ["//visibility:public"],
    )

    includes = ["include"] + [
        "include/%s" % postfix
        for postfix in include_postfixes
    ]

    _vcpkg_lib(
        name = "%s.release" % package,
        build = build,
        includes = includes,
        dir_prefix = "lib",
        deps = [
            "//%s/libs:release" % dep
            for dep in deps
        ],
        additional_obj_files = [
            ":vcpkg_%s_info" % package,
        ],
    )

    native.alias(
        name = "release",
        actual = ":%s.release" % package,
        visibility = ["//visibility:public"],
    )

    _vcpkg_lib(
        name = "%s.debug" % package,
        build = build,
        includes = includes,
        dir_prefix = "debug/lib",
        deps = [
            "//%s/libs:debug" % dep
            for dep in deps
        ],
        additional_obj_files = [
            ":vcpkg_%s_info" % package,
        ],
        visibility = ["//visibility:public"],
    )

    native.alias(
        name = "debug",
        actual = ":%s.debug" % package,
        visibility = ["//visibility:public"],
    )
