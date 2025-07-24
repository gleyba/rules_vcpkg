load("@vcpkg//:packages_info.bzl", "PACKAGES_INFO")

def _filter_qt_plugins(file):
    if "Qt6/plugins" not in file.path:
        return None

    if not file.path.endswith(".a") and not file.path.endswith(".o"):
        return None

    return file.path

def _filter_qt_plugins_debug(file):
    if "/debug/" not in file.path:
        return None

    return _filter_qt_plugins(file)

def _filter_qt_plugins_release(file):
    if "/debug/" in file.path:
        return None

    return _filter_qt_plugins(file)

def _copy_qt_plugins_impl(ctx):
    out = ctx.actions.declare_directory("%s" % ctx.attr.name)

    args = ctx.actions.args()

    args.add_all(
        ctx.files._package_output_dirs,
        map_each = _filter_qt_plugins_release if ctx.attr.is_release else _filter_qt_plugins_debug,
    )

    ctx.actions.run_shell(
        outputs = [out],
        inputs = ctx.files._package_output_dirs,
        arguments = [args],
        command = """\
for src in "$@"; do
    cp "$src" %s
done
""" % out.path,
    )

    return DefaultInfo(files = depset([out]))

_copy_qt_plugins = rule(
    implementation = _copy_qt_plugins_impl,
    attrs = {
        "is_release": attr.bool(mandatory = True),
        "_package_output_dirs": attr.label_list(
            allow_files = True,
            default = [
                inner["vcpkg_build"]
                for package, inner in PACKAGES_INFO.items()
                if package.startswith("qt")
            ],
        ),
    },
)

def copy_qt_plugins(**kwargs):
    _copy_qt_plugins(
        is_release = select({
            "@rules_vcpkg//vcpkg/vcpkg_utils:is_release_build": True,
            "//conditions:default": False,
        }),
        **kwargs
    )
