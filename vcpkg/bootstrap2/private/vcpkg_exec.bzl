load("//vcpkg/vcpkg_utils:exec_utils.bzl", _exec_check = "exec_check")

def vcpkg_exec(rctx, cmd, args, vcpkg_path, env = {}):
    vcpkg_env = {
        "VCPKG_DEFAULT_BINARY_CACHE": "%s/cache" % vcpkg_path,
        "VCPKG_ROOT": "%s/vcpkg" % vcpkg_path,
        "VCPKG_OVERLAY_TRIPLETS": "%s/overlay_triplets" % vcpkg_path,
    } | env

    vcpkg_args = [
        "--x-buildtrees-root=vcpkg/buildtrees",
        "--x-packages-root=packages",
        "--overlay-triplets=overlay_triplets",
        "--vcpkg-root=vcpkg",
    ]

    return _exec_check(
        rctx,
        "vckpg %s" % cmd,
        ["vcpkg/vcpkg", cmd] + args + vcpkg_args,
        vcpkg_env,
        vcpkg_path,
    )
