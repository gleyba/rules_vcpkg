load("//vcpkg:vcpkg.bzl", "vcpkg_package")
load("//vcpkg/bootstrap:bootstrap.bzl", _bootstrap = "bootstrap")
load("//vcpkg/bootstrap:bootstrap_toolchains.bzl", "bootstrap_toolchains")

bootstrap = tag_class(attrs = {
    "release": attr.string(doc = "The vcpkg version"),
    "sha256": attr.string(doc = "Shasum of vcpkg"),
})

install = tag_class(attrs = {
    "package": attr.string(doc = "Package to install"),
    "cpus": attr.string(
        default = "1",
        doc = "Cpu cores to use for package build, accept `HOST_CPUS` keyword",
    ),
})

def _vcpkg(mctx):
    cur_bootstrap = None
    packages = {}
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
            packages[install.package] = install.cpus

    if not cur_bootstrap:
        fail("No vcpkg release version to bootstrap specified")

    mctx.report_progress("Bootstrapping vcpkg release: %s" % cur_bootstrap.release)

    _bootstrap(
        name = "vcpkg",
        release = cur_bootstrap.release,
        sha256 = cur_bootstrap.sha256,
        packages = packages,
    )

    for package in packages.keys():
        vcpkg_package(
            name = "vcpkg_%s" % package,
            package = package,
        )

vcpkg = module_extension(
    implementation = _vcpkg,
    tag_classes = {
        "bootstrap": bootstrap,
        "install": install,
    },
)

vcpkg_external = module_extension(
    implementation = lambda _: bootstrap_toolchains(name = "vcpkg_external"),
)
