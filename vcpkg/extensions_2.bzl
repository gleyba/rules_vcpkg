load("//vcpkg/bootstrap/private:default_defs.bzl", "DEAULT_VCPKG_DISTRO_FIXUP_REPLACE", "DEFAULT_CONFIG_SETTINGS")
load("//vcpkg/bootstrap_2:bootstrap.bzl", "bootstrap")
load("//vcpkg/bootstrap_2:declare.bzl", "declare")

_bootstrap = tag_class(attrs = {
    "release": attr.string(doc = "The vcpkg version, either this or commit must be specified"),
    "commit": attr.string(doc = "The vcpkg commit, either this or version must be specified"),
    "sha256": attr.string(doc = "Shasum of vcpkg"),
    "verbose": attr.bool(doc = "If to print debug info", default = False),
    "allow_unsupported": attr.bool(doc = "Allow initialization of unsupported packages for host platform", default = False),
    "config_settings": attr.string_dict(
        doc = "Vcpkg triplet configuration settings",
        default = DEFAULT_CONFIG_SETTINGS,
    ),
    "vcpkg_distro_fixup_replace": attr.string_list_dict(
        doc = "Key is file path and value - list of sequential pairs of values, pattern to search and relace to",
        default = DEAULT_VCPKG_DISTRO_FIXUP_REPLACE,
    ),
})

_install = tag_class(attrs = {
    "package": attr.string(doc = "Package to install"),
})

def _vcpkg(mctx):
    # pu = platform_utils(mctx)
    cur_bootstrap = None
    packages = set()

    for mod in mctx.modules:
        for bootstrap_defs in mod.tags.bootstrap:
            if cur_bootstrap:
                if cur_bootstrap.release < bootstrap_defs.release:
                    tmp = cur_bootstrap
                    cur_bootstrap = bootstrap_defs
                    bootstrap_defs = tmp

                mctx.report_progress("Skip vcpkg release: %s, using a newer one" % bootstrap_defs.release)
            else:
                cur_bootstrap = bootstrap_defs

        for install in mod.tags.install:
            packages.add(install.package)

    if not cur_bootstrap:
        fail("No vcpkg release version to bootstrap specified")

    mctx.report_progress("Bootstrapping vcpkg release: %s" % cur_bootstrap.release)

    bootstrap(
        name = "vcpkg_bootstrap",
        release = cur_bootstrap.release,
        commit = cur_bootstrap.commit,
        sha256 = cur_bootstrap.sha256,
        config_settings = cur_bootstrap.config_settings,
    )

    declare(
        name = "vcpkg",
        bootstrap_repo = "vcpkg_bootstrap",
        bootstrap_lockfile = "@vcpkg_bootstrap//:BUILD.bazel",
    )

    return mctx.extension_metadata(
        root_module_direct_deps = [
            "vcpkg_bootstrap",
            "vcpkg",
        ],
        root_module_direct_dev_deps = [],
        reproducible = True,
    )

vcpkg = module_extension(
    implementation = _vcpkg,
    tag_classes = {
        "bootstrap": _bootstrap,
        "install": _install,
    },
)

# vcpkg = module_extension(
#     implementation = _vcpkg,
#     tag_classes = {
        
#     },
# )
