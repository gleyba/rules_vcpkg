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

def platform_utils(rctx, release):
    """Platform utils for vcpkg"""
    return struct(
        prefix = _platform_prefix(rctx),
        targets = _platform_targets(rctx),
        downloads = _platform_downloads(rctx),
    )
