load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "vcpkg_exec")

def collect_depend_info(rctx, bootstrap_ctx):
    res, err = vcpkg_exec(rctx, "depend-info", bootstrap_ctx.packages, bootstrap_ctx)
    if err:
        return None, err

    info_raw = res.stderr
    result = {}
    for package_info_raw in info_raw.split("\n"):
        if not package_info_raw:
            continue

        package_info_raw_parts = package_info_raw.split(": ")
        package = package_info_raw_parts[0]
        features_list = []
        features_start = package.find("[")
        if features_start != -1:
            if package[-1] != "]":
                fail("Can't parse features from: %s" % package)

            features_list = [
                f.strip()
                for f in package[features_start + 1:-1].split(",")
            ]
            package = package[0:features_start]

        deps_list = package_info_raw_parts[1].split(", ") if package_info_raw_parts[1] else []
        result[package] = struct(
            features = features_list,
            deps = deps_list,
        )

    return result, None
