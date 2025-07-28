load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")

MacosSDKInfo = provider(
    doc = "Information about Mac OS X SDK",
    fields = [
        "path",
        "files",
        "deployment_target",
    ],
)

def _macos_sdk_toolchain_impl(ctx):
    directory_info = ctx.attr.sysroot[DirectoryInfo]
    default_info = ctx.attr.sysroot[DefaultInfo]

    return platform_common.ToolchainInfo(
        macos_sdk_info = MacosSDKInfo(
            path = directory_info.path,
            files = default_info.files,
            deployment_target = ctx.attr.deployment_target,
        ),
    )

macos_sdk_toolchain = rule(
    implementation = _macos_sdk_toolchain_impl,
    attrs = {
        "sysroot": attr.label(
            mandatory = True,
            providers = [
                DirectoryInfo,
                DefaultInfo,
            ],
        ),
        "deployment_target": attr.string(
            mandatory = True,
        ),
    },
)
