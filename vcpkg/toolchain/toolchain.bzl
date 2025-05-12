VcpgInfo = provider(
    doc = "Information about how to invoke the barc compiler.",
    fields = [
        "vcpkg_tool",
        "vcpkg_manifest",
        "vcpkg_files",
        "cmake_files",
        # "default_install_files",
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
            # default_install_files = DefaultInfo(
            #     files = depset(ctx.files.default_install_files),
            # ),
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
        # "default_install_files": attr.label_list(allow_files = True),
    },
)
