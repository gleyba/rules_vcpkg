VcpgInfo = provider(
    doc = "Information about vcpkg toolchain.",
    fields = [
        "vcpkg_tool",
        "vcpkg_manifest",
        "vcpkg_files",
        "bin_dir",
        "config_settings",
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
            config_settings = ctx.attr.config_settings,
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
        "config_settings": attr.string_dict(
            doc = "Vcpkg triplet configuration settings",
            mandatory = True,
        ),
    },
)
