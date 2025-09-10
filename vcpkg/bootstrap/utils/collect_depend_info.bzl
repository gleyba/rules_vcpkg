load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "vcpkg_exec")
load("//vcpkg/vcpkg_utils:logging.bzl", "L")

def _parse_package_info(package_info_raw):
    if not package_info_raw:
        return None, None

    package_info_raw_parts = package_info_raw.split(": ")
    package = package_info_raw_parts[0]

    if package == "warning":
        return None, package_info_raw_parts[1]

    deps_list = package_info_raw_parts[1]

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

    deps_list = deps_list.split(", ") if deps_list else []

    return struct(
        package = package,
        features = features_list,
        deps = deps_list,
    ), None

def _add_to_result(result, package_info, bootstrap_ctx):
    result[package_info.package] = struct(
        features = package_info.features,
        deps = package_info.deps,
        cflags = bootstrap_ctx.packages_cflags.get(
            package_info.package,
            default = [],
        ),
        linkerflags = bootstrap_ctx.packages_linkerflags.get(
            package_info.package,
            default = [],
        ),
    )

def _collect_depend_info_exact(rctx, bootstrap_ctx, packages):
    res, err = vcpkg_exec(rctx, "depend-info", packages, bootstrap_ctx)
    if err:
        return None, err

    info_raw = res.stderr

    result = {}
    for package_info_raw in info_raw.split("\n"):
        if not package_info_raw:
            continue

        package_info, err = _parse_package_info(package_info_raw)
        if err != None:
            return None, err

        if not package_info.package in packages:
            continue

        _add_to_result(result, package_info, bootstrap_ctx)

    return result, None

def collect_depend_info(rctx, bootstrap_ctx):
    rctx.report_progress("Collecting VCPKG depend-info")

    res, err = vcpkg_exec(rctx, "depend-info", bootstrap_ctx.packages, bootstrap_ctx)
    if err:
        return None, err

    info_raw = res.stderr

    result = {}
    packages_to_requery = []

    for package_info_raw in info_raw.split("\n"):
        package_info, err = _parse_package_info(package_info_raw)
        if err != None:
            if bootstrap_ctx.verbose:
                L.warn(err)
            elif not bootstrap_ctx.allow_unsupported and "--allow-unsupported" in err:
                L.warn(err)

        if package_info == None:
            continue

        if package_info.package in bootstrap_ctx.packages_drop_features:
            drop_features = bootstrap_ctx.packages_drop_features[package_info.package]
            with_dropped_features = set(drop_features).difference(package_info.features)
            if len(with_dropped_features) != len(package_info.features):
                packages_to_requery.append("%s%s" % (
                    package_info.package,
                    "[%s]" % ",".join(with_dropped_features) if with_dropped_features else "",
                ))
                continue

        _add_to_result(result, package_info, bootstrap_ctx)

    if packages_to_requery:
        requery_result, err = _collect_depend_info_exact(rctx, bootstrap_ctx, packages_to_requery)
        if err != None:
            return None, err

        result |= requery_result

    return result, None
