load("//vcpkg:vcpkg.bzl", "vcpkg_package")
load("//vcpkg/bootstrap:bootstrap.bzl", call_bootstrap = "bootstrap")
load("//vcpkg/bootstrap:bootstrap_toolchains.bzl", "bootstrap_toolchains")
load("//vcpkg/bootstrap/macos:macos.bzl", _macos = "macos")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "add_or_extend_list_in_dict", "dict_to_kv_list")

_bootstrap = tag_class(attrs = {
    "release": attr.string(doc = "The vcpkg version, either this or commit must be specified"),
    "commit": attr.string(doc = "The vcpkg commit, either this or version must be specified"),
    "sha256": attr.string(doc = "Shasum of vcpkg"),
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
    "repo_fixups": attr.string_list(
        doc = """\
Bash script lines to execute before `install --only-downloads` called.
Helpful to copy some missing config files from ports directory to install one.
Environment variables 'PORT_DIR' and `INSTALL_DIR` will be available.
""",
    ),
    "port_patches": attr.label_list(
        doc = "Patches to apply to package port",
    ),
})

_configure_prefixed = tag_class(attrs = {
    "package_prefix": attr.string(doc = "Packages prefix to configure"),
    "include_postfixes": attr.string_list(doc = "Postfixes to add to includes"),
    "collect_outputs": attr.string_dict(
        doc = """\
Directories prefix in outputs to add collect to single rule returning `DefaultInfo` with symlinks".
A key is name of output rule and value is directory prefix to collect.
""",
    ),
})

def _vcpkg(mctx):
    cur_bootstrap = None
    packages = set()
    packages_cpus = {}
    packages_repo_fixups = {}
    packages_ports_patches = {}
    pp_to_include_postfixes = {}
    pp_to_collect_outputs = {}
    for mod in mctx.modules:
        for bootstrap in mod.tags.bootstrap:
            if cur_bootstrap:
                if cur_bootstrap.release < bootstrap.release:
                    tmp = cur_bootstrap
                    cur_bootstrap = bootstrap
                    bootstrap = tmp

                mctx.report_progress("Skip vcpkg release: %s, using a newer one" % bootstrap.release)
            else:
                cur_bootstrap = bootstrap

        for install in mod.tags.install:
            packages.add(install.package)

        for configure in mod.tags.configure:
            if configure.cpus:
                packages_cpus[configure.package] = configure.cpus

            add_or_extend_list_in_dict(
                packages_repo_fixups,
                configure.package,
                configure.repo_fixups,
            )

            for patch in configure.port_patches:
                packages_ports_patches[patch] = configure.package

        for configure_prefixed in mod.tags.configure_prefixed:
            add_or_extend_list_in_dict(
                pp_to_include_postfixes,
                configure_prefixed.package_prefix,
                configure_prefixed.include_postfixes,
            )

            add_or_extend_list_in_dict(
                pp_to_collect_outputs,
                configure_prefixed.package_prefix,
                dict_to_kv_list(configure_prefixed.collect_outputs),
            )

    if not cur_bootstrap:
        fail("No vcpkg release version to bootstrap specified")

    mctx.report_progress("Bootstrapping vcpkg release: %s" % cur_bootstrap.release)

    call_bootstrap(
        name = "vcpkg",
        release = cur_bootstrap.release,
        commit = cur_bootstrap.commit,
        sha256 = cur_bootstrap.sha256,
        packages = list(packages),
        packages_cpus = packages_cpus,
        packages_repo_fixups = packages_repo_fixups,
        packages_ports_patches = packages_ports_patches,
        pp_to_include_postfixes = pp_to_include_postfixes,
        pp_to_collect_outputs = pp_to_collect_outputs,
        external_bins = "@vcpkg_external//bin",
    )

    for package in packages:
        vcpkg_package(
            name = "vcpkg_%s" % package,
            package = package,
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

macos = _macos
