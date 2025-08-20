def _is_macos(rctx):
    return rctx.os.name.lower().startswith("mac")

def _is_linux(rctx):
    return rctx.os.name.lower().startswith("linux")

def _is_arm64(rctx):
    return rctx.os.arch in ["aarch64", "arm64"]

def _is_amd64(rctx):
    return rctx.os.arch in ["x86_64", "amd64"]

def _platform_prefix(rctx):
    os = None
    if _is_macos(rctx):
        os = "osx"

    if _is_linux(rctx):
        os = "linux"

    arch = None
    if _is_arm64(rctx):
        arch = "arm64"

    if _is_amd64(rctx):
        arch = "amd64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return "%s-%s" % (arch, os)

def _platform_targets(rctx):
    os = None
    if _is_macos(rctx):
        os = "@platforms//os:macos"

    if _is_linux(rctx):
        os = "@platforms//os:linux"

    arch = None
    if _is_arm64(rctx):
        arch = "@platforms//cpu:aarch64"

    if _is_amd64(rctx):
        arch = "@platforms//cpu:x86_64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(os = os, arch = arch)

def _platform_downloads(rctx):
    url_tpl = None
    sha_key = None
    if _is_linux(rctx):
        if _is_arm64(rctx):
            url_tpl = "https://github.com/microsoft/vcpkg-tool/releases/download/%s/vcpkg-glibc-arm64"
            sha_key = "VCPKG_GLIBC_ARM64_SHA"

        if _is_amd64(rctx):
            url_tpl = "https://github.com/microsoft/vcpkg-tool/releases/download/%s/vcpkg-glibc"
            sha_key = "VCPKG_GLIBC_SHA"

    if _is_macos(rctx):
        url_tpl = "https://github.com/microsoft/vcpkg-tool/releases/download/%s/vcpkg-macos"
        sha_key = "VCPKG_MACOS_SHA"

    if not url_tpl or not sha_key:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(url_tpl = url_tpl, sha_key = sha_key)

def _host_cpus_cout(rctx):
    if _is_macos(rctx):
        return rctx.execute(["sysctl", "-n", "hw.ncpu"]).stdout.strip()

    if _is_linux(rctx):
        return rctx.execute(["nproc"]).stdout.strip()

    fail("Unsupported OS: %s" % rctx.os.name)

platform_defs = struct(
    os = struct(
        macos = struct(
            short_name = "osx",
            long_name = "Darwin",
            name = "macos",
        ),
        linux = struct(
            short_name = "linux",
            long_name = "Linux",
            name = "linux",
        ),
    ),
    arch = struct(
        amd64 = struct(
            short_name = "x64",
            long_name = "x86_64",
            name = "amd64",
        ),
        arm64 = struct(
            short_name = "arm64",
            long_name = "arm64",
            name = "arm64",
        ),
    ),
)

def _to_substitutions(os, arch):
    return {
        "%%SYSTEM_NAME_SHORT%%": os.short_name,
        "%%SYSTEM_NAME_LONG%%": os.long_name,
        "%%ARCH_SHORT%%": arch.short_name,
        "%%ARCH_LONG%%": arch.long_name,
    }

def _to_triplet(os, arch):
    return "%s-%s" % (
        arch.short_name,
        os.short_name,
    )

def _to_definitions(os, arch):
    return struct(
        substitutions = _to_substitutions(os, arch),
        triplet = _to_triplet(os, arch),
        os = os,
        arch = arch,
    )

definitions = struct(
    linux = struct(
        amd64 = _to_definitions(platform_defs.os.linux, platform_defs.arch.amd64),
        arm64 = _to_definitions(platform_defs.os.linux, platform_defs.arch.arm64),
    ),
    macos = struct(
        amd64 = _to_definitions(platform_defs.os.macos, platform_defs.arch.amd64),
        arm64 = _to_definitions(platform_defs.os.macos, platform_defs.arch.arm64),
    ),
)

def _definitions(rctx):
    if _is_macos(rctx):
        if _is_arm64(rctx):
            return definitions.macos.arm64
        elif _is_amd64(rctx):
            return definitions.macos.amd64
    elif _is_linux(rctx):
        if _is_arm64(rctx):
            return definitions.linux.arm64
        elif _is_amd64(rctx):
            return definitions.linux.amd64

    fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

def _triplet_template(rctx):
    if _is_macos(rctx):
        return Label("//vcpkg/toolchain/triplets:macos.tmpl.cmake")
    elif _is_linux(rctx):
        return Label("//vcpkg/toolchain/triplets:linux.tmpl.cmake")
    fail("Unsupported OS: %s" % rctx.os.name)

def _match_os(rctx, os):
    if os == "*":
        return True

    if os == "macos":
        return _is_macos(rctx)

    if os == "linux":
        return _is_linux(rctx)

    fail("Unsupported requested OS to match: %s" % os)

def _match_arch(rctx, arch):
    if arch == "*":
        return True

    if arch == "arm64":
        return _is_arm64(rctx)

    if arch == "amd64":
        return _is_amd64(rctx)

    fail("Unsupported requested ARCH to match: %s" % arch)

def _match_platform(rctx, os, arch):
    return _match_os(rctx, os) and _match_arch(rctx, arch)

def platform_utils(rctx):
    """Platform utils for vcpkg"""
    return struct(
        prefix = _platform_prefix(rctx),
        targets = _platform_targets(rctx),
        downloads = _platform_downloads(rctx),
        host_cpus_count = lambda: _host_cpus_cout(rctx),
        triplet_template = _triplet_template(rctx),
        definitions = _definitions(rctx),
        match_platform = lambda os, arch: _match_platform(rctx, os, arch),
    )
