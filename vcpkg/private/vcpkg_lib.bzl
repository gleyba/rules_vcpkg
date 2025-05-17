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
    args.add(ctx.file._empty_lib)

    ctx.actions.run(
        tools = [
            ctx.executable._extract_package_outputs,
        ],
        inputs = [
            package_info.output,
            ctx.file._empty_lib,
        ],
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
        "_extract_package_outputs": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:extract_package_outputs",
            executable = True,
            cfg = "exec",
            doc = "Tool to prepare vcpkg install directory structure",
        ),
        "_empty_lib": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:_",
            allow_single_file = True,
            doc = "Just an empty lib stub",
        ),
    },
)

def vcpkg_lib(name, build, deps, **kwargs):
    _extract_package_outputs(
        name = "%s_headers" % name,
        build = build,
        dir_prefix = "include",
        collect_type = "headers",
    )
    _extract_package_outputs(
        name = "%s_release_lib" % name,
        build = build,
        dir_prefix = "lib",
        collect_type = "libs",
    )
    cc_import(
        name = "%s_release_import" % name,
        hdrs = [":%s_headers" % name],
        objects = [":%s_release_lib" % name],
    )
    cc_library(
        name = "%s_release" % name,
        deps = [":%s_release_import" % name] + [
            "%s_release" % dep
            for dep in deps
        ],
        includes = ["%s_headers" % name],
        **kwargs
    )
    _extract_package_outputs(
        name = "%s_debug_lib" % name,
        build = build,
        dir_prefix = "debug/lib",
        collect_type = "libs",
    )
    cc_import(
        name = "%s_debug_import" % name,
        hdrs = [":%s_headers" % name],
        objects = [":%s_debug_lib" % name],
    )
    cc_library(
        name = "%s_debug" % name,
        deps = [":%s_debug_import" % name] + [
            "%s_debug" % dep
            for dep in deps
        ],
        includes = ["%s_headers" % name],
        **kwargs
    )
