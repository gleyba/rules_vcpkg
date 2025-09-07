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
        return res, None

    return None, "\n".join([
        "%s failed with code %d" % (mnemo, res.return_code),
        "stdout: %s" % res.stdout,
        "stderr: %s" % res.stderr,
    ])

def vcpkg_exec(rctx, cmd, args, bootstrap_ctx):
    full_path = str(rctx.path(bootstrap_ctx.output))

    vcpkg_env = {
        # "X_VCPKG_REGISTRIES_CACHE": "%s/registries" % workdir,
        "PATH": bootstrap_ctx.external_bins,
        "VCPKG_DEFAULT_BINARY_CACHE": "%s/cache" % full_path,
        "VCPKG_ROOT": "%s/vcpkg" % full_path,
        "VCPKG_DOWNLOADS": "%s/downloads" % bootstrap_ctx.tmpdir,
        "VCPKG_OVERLAY_TRIPLETS": "%s/overlay_triplets" % full_path,
    }

    vcpkg_args = [
        "--x-buildtrees-root=vcpkg/buildtrees",
        "--x-install-root=%s/install" % bootstrap_ctx.tmpdir,
        "--x-packages-root=packages",
        "--downloads-root=%s/downloads" % bootstrap_ctx.tmpdir,
        "--overlay-triplets=overlay_triplets",
        "--vcpkg-root=vcpkg",
    ]

    if cmd == "install" and bootstrap_ctx.allow_unsupported:
        vcpkg_args.append("--allow-unsupported")

    return exec_check(
        rctx,
        "vckpg %s" % cmd,
        ["vcpkg/vcpkg", cmd] + args + vcpkg_args,
        vcpkg_env,
        full_path,
    )
