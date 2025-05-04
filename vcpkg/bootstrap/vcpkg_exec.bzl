def exec_check(
        rctx,
        mnemo,
        args,
        env = {},
        workdir = ""):
    res = rctx.execute(
        args,
        environment = env,
        working_directory = workdir,
    )

    if res.return_code == 0:
        return res

    fail("\n".join([
        "%s failed with code %d" % (mnemo, res.return_code),
        "stdout: %s" % res.stdout,
        "stderr: %s" % res.stderr,
    ]))

def vcpkg_exec(rctx, cmd, args, workdir):
    full_path = str(rctx.path(workdir))

    vcpkg_env = {
        # "X_VCPKG_REGISTRIES_CACHE": "%s/registries" % workdir,
        "VCPKG_DEFAULT_BINARY_CACHE": "%s/cache" % full_path,
        "VCPKG_ROOT": "%s/vcpkg" % full_path,
        "VCPKG_DOWNLOADS": "%s/vcpkg/downloads" % full_path,
        # "VCPKG_OVERLAY_PORTS": "%s/overlay_ports" % workdir,
    }

    vcpkg_args = [
        "--x-buildtrees-root=vcpkg/buildtrees",
        "--x-install-root=install",
        "--x-packages-root=packages",
        "--downloads-root=vcpkg/downloads",
        # "--overlay-ports=overlay_ports",
        "--vcpkg-root=vcpkg",
    ]

    return exec_check(
        rctx,
        "vckpg %s" % cmd,
        ["vcpkg/vcpkg", cmd] + args + vcpkg_args,
        vcpkg_env,
        full_path,
    )
