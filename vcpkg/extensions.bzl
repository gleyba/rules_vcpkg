load("//vcpkg/bootstrap:bootstrap.bzl", "bootstrap")
load("//vcpkg/bootstrap:bootstrap_toolchains.bzl", "bootstrap_toolchains")
load("//vcpkg/bootstrap:declare.bzl", "declare")
load("//vcpkg/bootstrap/external:cc_toolchain_util.bzl", "cc_toolchain_util")
load("//vcpkg/bootstrap/private:default_defs.bzl", "DEAULT_VCPKG_DISTRO_FIXUP_REPLACE", "DEFAULT_CONFIG_SETTINGS")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "add_or_extend_list_in_dict")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

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
    "drop_features": attr.string_list(
        doc = "Features to force drop on package",
    ),
    "cflags": attr.string_list(
        doc = "Additional c flags to propagate to build, are not transitive",
    ),
    "linkerflags": attr.string_list(
        doc = "Additional linker flags to propagate to build, are not transitive",
    ),
    "override_sources": attr.string(
        doc = "Override sources location, useful for debug",
    ),
    "overlay_sources": attr.label_list(
        doc = "Overlay sources to add to package srcs, created with `pkg_files`",
    ),
    "os": attr.string(
        default = "*",
        doc = "Filter by os, e.g. macos, linux, or '*' for any",
    ),
    "arch": attr.string(
        default = "*",
        doc = "Filter by arch, e.g. amd64, arm64, or '*' for any",
    ),
})

_configure_prefixed = tag_class(attrs = {
    "package_prefix": attr.string(doc = "Packages prefix to configure"),
    "include_postfixes": attr.string_list(doc = "Postfixes to add to includes"),
})

def _vcpkg(mctx):
    pu = platform_utils(mctx)
    cur_bootstrap = None
    packages = set()
    packages_cpus = {}
    packages_install_fixups = {}
    packages_buildtree_fixups = {}
    packages_ports_patches = {}
    packages_src_patches = {}
    packages_drop_features = {}
    packages_cflags = {}
    packages_linkerflags = {}
    packages_override_sources = {}
    packages_overlay_sources = {}
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
            if not pu.match_platform(configure.os, configure.arch):
                continue

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

            add_or_extend_list_in_dict(
                packages_drop_features,
                configure.package,
                configure.drop_features,
            )

            add_or_extend_list_in_dict(
                packages_cflags,
                configure.package,
                configure.cflags,
            )

            add_or_extend_list_in_dict(
                packages_linkerflags,
                configure.package,
                configure.linkerflags,
            )

            for patch in configure.port_patches:
                packages_ports_patches[patch] = configure.package

            for patch in configure.src_patches:
                packages_src_patches[patch] = configure.package

            if configure.override_sources:
                if configure.package in packages_override_sources:
                    fail("Sources location override set twice for %s" % configure.package)

                packages_override_sources[configure.package] = configure.override_sources

            for overlay_src in configure.overlay_sources:
                packages_overlay_sources[Label(overlay_src)] = configure.package

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
        packages_drop_features = packages_drop_features,
        packages_ports_patches = packages_ports_patches,
        packages_src_patches = packages_src_patches,
        external_bins = "@vcpkg_external//bin",
        verbose = cur_bootstrap.verbose,
        allow_unsupported = cur_bootstrap.allow_unsupported,
        config_settings = cur_bootstrap.config_settings,
        vcpkg_distro_fixup_replace = cur_bootstrap.vcpkg_distro_fixup_replace,
    )

    declare(
        name = "vcpkg",
        bootstrap_repo = "vcpkg_bootstrap",
        depend_info = "@vcpkg_bootstrap//:depend_info.json",
        packages = list(packages),
        packages_cpus = packages_cpus,
        packages_cflags = packages_cflags,
        packages_linkerflags = packages_linkerflags,
        packages_override_sources = packages_override_sources,
        packages_overlay_sources = packages_overlay_sources,
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

def _vcpkg_external_impl(_mctx):
    bootstrap_toolchains(name = "vcpkg_external")
    cc_toolchain_util(name = "cc_toolchain_util.bzl")

vcpkg_external = module_extension(
    implementation = _vcpkg_external_impl,
)
