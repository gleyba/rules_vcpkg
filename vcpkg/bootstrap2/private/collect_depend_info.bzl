load("//vcpkg/bootstrap2/private:vcpkg_exec.bzl", "vcpkg_exec")

def _parse_package_info(package_info_raw):
    if not package_info_raw:
        return None, None, None

    package_info_raw_parts = package_info_raw.split(": ")
    package = package_info_raw_parts[0]

    if package == "warning":
        return None, package_info_raw_parts[1], None

    deps_list = package_info_raw_parts[1]

    features_list = []
    features_start = package.find("[")
    if features_start != -1:
        if package[-1] != "]":
            return None, None, "Can't parse features from: %s" % package

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
    ), None, None

def _add_to_result(result, package_info):
    result[package_info.package] = struct(
        features = package_info.features,
        deps = package_info.deps,
    )

def _collect_depend_info_exact(rctx, packages, vcpkg_path):
    res, err = vcpkg_exec(rctx, "depend-info", packages, vcpkg_path)
    if err:
        return None, None, err

    info_raw = res.stderr

    result = {}
    warnings = []
    for package_info_raw in info_raw.split("\n"):
        if not package_info_raw:
            continue

        package_info, warn, err = _parse_package_info(package_info_raw)
        if warn != None:
            warnings.append(warn)

        if err != None:
            return None, warnings, None

        if not package_info.package in packages:
            continue

        _add_to_result(result, package_info)

    return result, warnings, None

def collect_depend_info(rctx, packages, packages_drop_features, vcpkg_path):
    rctx.report_progress("Collecting VCPKG depend-info")

    res, err = vcpkg_exec(rctx, "depend-info", packages, vcpkg_path)
    if err:
        return None, None, [err]

    info_raw = res.stderr

    result = {}
    all_warnings = []
    packages_to_requery = []

    for package_info_raw in info_raw.split("\n"):
        package_info, warnings, err = _parse_package_info(package_info_raw)
        if warnings:
            all_warnings += warnings

        if err != None:
            return None, all_warnings, err

        if package_info == None:
            continue

        if package_info.package in packages_drop_features:
            drop_features = packages_drop_features[package_info.package]
            with_dropped_features = set(drop_features).difference(package_info.features)
            if len(with_dropped_features) != len(package_info.features):
                packages_to_requery.append("%s%s" % (
                    package_info.package,
                    "[%s]" % ",".join(with_dropped_features) if with_dropped_features else "",
                ))
                continue

        _add_to_result(result, package_info)

    if packages_to_requery:
        requery_result, err = _collect_depend_info_exact(rctx, packages_to_requery, vcpkg_path)
        if err != None:
            return None, err

        result |= requery_result

    return result, all_warnings, None
