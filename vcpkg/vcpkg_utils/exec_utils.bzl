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
