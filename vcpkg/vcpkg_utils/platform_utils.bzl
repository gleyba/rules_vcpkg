def _platform_prefix(rctx):
    os = None
    if rctx.os.name.startswith("mac"):
        os = "osx"

    arch = None
    if rctx.os.arch == "aarch64":
        arch = "arm64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return "%s-%s" % (arch, os)

def _platform_targets(rctx):
    os = None
    if rctx.os.name.startswith("mac"):
        os = "@platforms//os:macos"

    arch = None
    if rctx.os.arch == "aarch64":
        arch = "@platforms//cpu:arm64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(os = os, arch = arch)

def _platform_downloads(rctx):
    url_tpl = None
    sha_key = None
    if rctx.os.name.startswith("mac"):
        url_tpl = "https://github.com/microsoft/vcpkg-tool/releases/download/%s/vcpkg-macos"
        sha_key = "VCPKG_MACOS_SHA"

    if not url_tpl or not sha_key:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(url_tpl = url_tpl, sha_key = sha_key)

def _host_cpus_cout(rctx):
    return rctx.execute(["sysctl", "-n", "hw.ncpu"]).stdout.strip()

def platform_utils(rctx):
    """Platform utils for vcpkg"""
    return struct(
        prefix = _platform_prefix(rctx),
        targets = _platform_targets(rctx),
        downloads = _platform_downloads(rctx),
        host_cpus_count = lambda: _host_cpus_cout(rctx),
    )

VcpkgPlatformTrippletProvider = provider(
    doc = "Vcpkg platform triplet provider",
    fields = ["triplet"],
)

vcpkg_platform_triplet = rule(
    implementation = lambda ctx: VcpkgPlatformTrippletProvider(triplet = ctx.attr.triplet),
    attrs = {"triplet": attr.string(doc = "Vcpkg platform triplet")},
)
