load("//vcpkg/bootstrap:vcpkg_exec.bzl", "vcpkg_exec")

def collect_depend_info(rctx, workdir, packages):
    info_raw = vcpkg_exec(rctx, "depend-info", packages, workdir).stderr
    result = {}
    for package_info_raw in info_raw.split("\n"):
        if not package_info_raw:
            continue

        package_info_raw_parts = package_info_raw.split(": ")
        package = package_info_raw_parts[0]
        deps_list = package_info_raw_parts[1].split(", ") if package_info_raw_parts[1] else []
        result[package] = deps_list

    return result

# def _collect_depend_info_impl(rctx):
#     print(collect_depend_info(rctx, rctx.attr.path, rctx.attr.packages))
#     rctx.file("BUILD.bazel", "")

# collect_depend_info_debug = repository_rule(
#     implementation = _collect_depend_info_impl,
#     attrs = {
#         "path": attr.string(
#             mandatory = True,
#             doc = "Path to the vcpkg root",
#         ),
#         "packages": attr.string_list(
#             mandatory = True,
#             doc = "Packages to collect depend info for",
#         ),
#     },
# )
