load("//vcpkg/bootstrap2/private:collect_depend_info.bzl", "collect_depend_info")
load("//vcpkg/vcpkg_utils:logging.bzl", "L")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "PLATFORMS_PAIRS_HIERARCHICAL")

def _platform_prefix(os, arch):
    return "%s%s" % (
        "%s_" % os if os != "*" else "",
        "%s_" % arch if arch != "*" else "",
    )

def _dict_difference(first, second):
    return dict(set(first.items()) ^ set(second.items()))

def generate_lockfile_data(rctx, packages, bootstrap_configure_ctx):
    data = {}
    for platform_pair in PLATFORMS_PAIRS_HIERARCHICAL.keys():
        data[platform_pair] = {
            "packages_drop_features": bootstrap_configure_ctx.packages_drop_features(*platform_pair),
        }

    result_data_raw = {}
    result_data = {}
    for platform_pair, parent_platfortm_pair in PLATFORMS_PAIRS_HIERARCHICAL.items():
        cur_data = data[platform_pair]

        if parent_platfortm_pair != None:
            parent_data = data[parent_platfortm_pair]
            if cur_data == parent_data:
                continue

        result, warnings, err = collect_depend_info(
            rctx,
            packages,
            cur_data["packages_drop_features"],
            str(rctx.path("")),
        )
        for warning in warnings:
            if rctx.attr.allow_unsupported and "--allow-unsupported" in warning:
                continue
            L.warn(warning)

        if err != None:
            return None, err

        result_data_raw[platform_pair] = result
        if parent_platfortm_pair == None:
            result_data["%spackages" % _platform_prefix(*platform_pair)] = result
        else:
            parent_result = result_data_raw[parent_platfortm_pair]
            result_data["%spackages" % _platform_prefix(*platform_pair)] = _dict_difference(parent_result, result)

    return result_data, None
