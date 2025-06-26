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

    arch = None
    if _is_arm64(rctx):
        arch = "arm64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return "%s-%s" % (arch, os)

def _platform_targets(rctx):
    os = None
    if _is_macos(rctx):
        os = "@platforms//os:macos"

    arch = None
    if _is_arm64(rctx):
        arch = "@platforms//cpu:arm64"

    if not os or not arch:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(os = os, arch = arch)

def _platform_downloads(rctx):
    url_tpl = None
    sha_key = None
    if _is_macos(rctx):
        url_tpl = "https://github.com/microsoft/vcpkg-tool/releases/download/%s/vcpkg-macos"
        sha_key = "VCPKG_MACOS_SHA"

    if not url_tpl or not sha_key:
        fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

    return struct(url_tpl = url_tpl, sha_key = sha_key)

def _host_cpus_cout(rctx):
    return rctx.execute(["sysctl", "-n", "hw.ncpu"]).stdout.strip()

platform_defs = struct(
    os = struct(
        macos = struct(
            short_name = "osx",
            long_name = "Darwin",
        ),
        linux = struct(
            short_name = "linux",
            long_name = "Linux",
        ),
    ),
    arch = struct(
        amd64 = struct(
            short_name = "x64",
            long_name = "x86_64",
        ),
        arm64 = struct(
            short_name = "arm64",
            long_name = "arm64",
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

def _to_cmake_defs(os, arch):
    return struct(
        substitutions = _to_substitutions(os, arch),
        triplet = _to_triplet(os, arch),
    )

cmake_definitions = struct(
    linux = struct(
        amd64 = _to_cmake_defs(platform_defs.os.linux, platform_defs.arch.amd64),
        arm64 = _to_cmake_defs(platform_defs.os.linux, platform_defs.arch.arm64),
    ),
    macos = struct(
        amd64 = _to_cmake_defs(platform_defs.os.macos, platform_defs.arch.amd64),
        arm64 = _to_cmake_defs(platform_defs.os.macos, platform_defs.arch.arm64),
    ),
)

def _cmake_definitions(rctx):
    if _is_macos(rctx):
        if _is_arm64(rctx):
            return cmake_definitions.macos.arm64
        elif _is_amd64(rctx):
            return cmake_definitions.macos.amd64
    elif _is_linux(rctx):
        if _is_arm64(rctx):
            return cmake_definitions.linux.arm64
        elif _is_amd64(rctx):
            return cmake_definitions.linux.amd64

    fail("Unsupported OS/arch: %s/%s" % (rctx.os.name, rctx.os.arch))

def _triplet_template(rctx):
    if _is_macos(rctx):
        return Label("//vcpkg/toolchain/triplets:macos.tmpl.cmake")
    elif _is_linux(rctx):
        return Label("//vcpkg/toolchain/triplets:linux.tmpl.cmake")
    fail("Unsupported OS: %s" % rctx.os.name)

def platform_utils(rctx):
    """Platform utils for vcpkg"""
    return struct(
        prefix = _platform_prefix(rctx),
        targets = _platform_targets(rctx),
        downloads = _platform_downloads(rctx),
        host_cpus_count = lambda: _host_cpus_cout(rctx),
        triplet_template = _triplet_template(rctx),
        cmake_definitions = _cmake_definitions(rctx),
    )
