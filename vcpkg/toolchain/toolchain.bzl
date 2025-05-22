VcpgInfo = provider(
    doc = "Information about how to invoke the barc compiler.",
    fields = [
        "vcpkg_tool",
        "vcpkg_manifest",
        "vcpkg_files",
        "cmake_files",
        "host_cpu_count",
    ],
)

def _vcpkg_toolchain_impl(ctx):
    return platform_common.ToolchainInfo(
        vcpkg_info = VcpgInfo(
            vcpkg_tool = ctx.file.vcpkg_tool,
            vcpkg_manifest = ctx.file.vcpkg_manifest,
            vcpkg_files = DefaultInfo(
                files = depset(ctx.files.vcpkg_files),
            ),
            cmake_files = DefaultInfo(
                files = depset(ctx.files.cmake_files),
            ),
            host_cpu_count = ctx.attr.host_cpu_count,
        ),
    )

vcpkg_toolchain = rule(
    implementation = _vcpkg_toolchain_impl,
    attrs = {
        "vcpkg_tool": attr.label(
            allow_single_file = True,
            doc = "Path to the vcpkg tool",
        ),
        "vcpkg_manifest": attr.label(
            allow_single_file = True,
            doc = "Path to the vcpkg manifest",
        ),
        "vcpkg_files": attr.label_list(allow_files = True),
        "cmake_files": attr.label_list(allow_files = True),
        "host_cpu_count": attr.int(
            mandatory = True,
            doc = "Number of CPU cores on machine",
        ),
    },
)
