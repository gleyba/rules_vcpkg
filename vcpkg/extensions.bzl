load("//vcpkg/bootstrap:bootstrap.bzl", "bootstrap")
load("//vcpkg/bootstrap:bootstrap_toolchains.bzl", "bootstrap_toolchains")
load("//vcpkg/bootstrap:declare.bzl", "declare")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "add_or_extend_list_in_dict")

_bootstrap = tag_class(attrs = {
    "release": attr.string(doc = "The vcpkg version, either this or commit must be specified"),
    "commit": attr.string(doc = "The vcpkg commit, either this or version must be specified"),
    "sha256": attr.string(doc = "Shasum of vcpkg"),
    "verbose": attr.bool(doc = "If to print debug info", default = False),
})

_install = tag_class(attrs = {
    "package": attr.string(doc = "Package to install"),
})

_configure = tag_class(attrs = {
    "package": attr.string(doc = "Package to configure"),
    "cpus": attr.string(
        default = "1",
        doc = "Cpu cores to use for package build, accept `HOST_CPUS` keyword",
    ),
    "install_fixups": attr.string_list(
        doc = """\
Bash script lines to execute before `install --only-downloads` called.
Helpful to copy some missing config files from ports directory to install one.
Environment variables 'PORT_DIR', and `INSTALL_DIR` will be available.
""",
    ),
    "buildtree_fixups": attr.string_list(
        doc = """\
Bash script lines to execute after `install --only-downloads` called.
Helpful to delete non-hermetic data or dangled symlinks.
Environment variable 'BUILDTREE_DIR' and will be available.
""",
    ),
    "port_patches": attr.label_list(
        doc = "Patches to apply to package port",
    ),
    "src_patches": attr.label_list(
        doc = "Patches to apply to package src dir",
    ),
})

_configure_prefixed = tag_class(attrs = {
    "package_prefix": attr.string(doc = "Packages prefix to configure"),
    "include_postfixes": attr.string_list(doc = "Postfixes to add to includes"),
})

def _vcpkg(mctx):
    cur_bootstrap = None
    packages = set()
    packages_cpus = {}
    packages_install_fixups = {}
    packages_buildtree_fixups = {}
    packages_ports_patches = {}
    packages_src_patches = {}
    pp_to_include_postfixes = {}
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

        for configure in mod.tags.configure:
            if configure.cpus:
                packages_cpus[configure.package] = configure.cpus

            add_or_extend_list_in_dict(
                packages_install_fixups,
                configure.package,
                configure.install_fixups,
            )

            add_or_extend_list_in_dict(
                packages_buildtree_fixups,
                configure.package,
                configure.buildtree_fixups,
            )

            for patch in configure.port_patches:
                packages_ports_patches[patch] = configure.package

            for patch in configure.src_patches:
                packages_src_patches[patch] = configure.package

        for configure_prefixed in mod.tags.configure_prefixed:
            add_or_extend_list_in_dict(
                pp_to_include_postfixes,
                configure_prefixed.package_prefix,
                configure_prefixed.include_postfixes,
            )

    if not cur_bootstrap:
        fail("No vcpkg release version to bootstrap specified")

    mctx.report_progress("Bootstrapping vcpkg release: %s" % cur_bootstrap.release)

    bootstrap(
        name = "vcpkg_bootstrap",
        release = cur_bootstrap.release,
        commit = cur_bootstrap.commit,
        sha256 = cur_bootstrap.sha256,
        packages = list(packages),
        packages_install_fixups = packages_install_fixups,
        packages_buildtree_fixups = packages_buildtree_fixups,
        packages_ports_patches = packages_ports_patches,
        packages_src_patches = packages_src_patches,
        external_bins = "@vcpkg_external//bin",
        verbose = cur_bootstrap.verbose,
    )

    declare(
        name = "vcpkg",
        bootstrap_repo = "vcpkg_bootstrap",
        depend_info = "@vcpkg_bootstrap//:depend_info.json",
        packages = list(packages),
        packages_cpus = packages_cpus,
        pp_to_include_postfixes = pp_to_include_postfixes,
    )

vcpkg = module_extension(
    implementation = _vcpkg,
    tag_classes = {
        "bootstrap": _bootstrap,
        "install": _install,
        "configure": _configure,
        "configure_prefixed": _configure_prefixed,
    },
)

vcpkg_external = module_extension(
    implementation = lambda _: bootstrap_toolchains(name = "vcpkg_external"),
)
