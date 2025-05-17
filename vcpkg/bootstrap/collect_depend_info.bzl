load("//vcpkg/bootstrap:vcpkg_exec.bzl", "vcpkg_exec")

def collect_depend_info(rctx, workdir, packages):
    info_raw = vcpkg_exec(rctx, "depend-info", packages, workdir).stderr
    result = {}
    for package_info_raw in info_raw.split("\n"):
        if not package_info_raw:
            continue

        package_info_raw_parts = package_info_raw.split(": ")
        package = package_info_raw_parts[0]
        flavoured = package.find("[")
        if flavoured != -1:
            package = package[0:flavoured]

        deps_list = package_info_raw_parts[1].split(", ") if package_info_raw_parts[1] else []
        result[package] = deps_list

    return result
