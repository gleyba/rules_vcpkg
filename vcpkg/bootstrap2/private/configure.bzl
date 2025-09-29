load("//vcpkg/vcpkg_utils:format_utils.bzl", "add_or_extend_list_in_dict")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "PLATFORMS_PAIRS")

configure = tag_class(attrs = {
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
        values = ["*", "macos", "linux"],
        doc = "Filter by os, e.g. macos, linux, or '*' for any",
    ),
    "arch": attr.string(
        default = "*",
        values = ["*", "amd64", "arm64"],
        doc = "Filter by arch, e.g. amd64, arm64, or '*' for any",
    ),
})

def _repo_attr_prefix_for(os, arch):
    return "%s%s" % (
        "%s_" % os if os != "*" else "",
        "%s_" % arch if arch != "*" else "",
    )

def _gen_bootstrap_repo_attrs_for(os, arch):
    name_prefix = _repo_attr_prefix_for(os, arch)

    doc_postfix = "for %s os and %s arch" % (
        os if os != "*" else "any",
        arch if arch != "*" else "any",
    )

    return {
        "%spackages_drop_features" % name_prefix: attr.string_list_dict(
            mandatory = False,
            doc = "Features to force drop on package %s" % doc_postfix,
        ),
        "%spackages_port_patches" % name_prefix: attr.label_keyed_string_dict(
            mandatory = False,
            doc = "Patches to apply to port directory %s" % doc_postfix,
        ),
    }

def _gen_bootstrap_repo_attrs():
    result = {}
    for os, arch in PLATFORMS_PAIRS:
        result |= _gen_bootstrap_repo_attrs_for(os, arch)
    return result

BOOTSTRAP_CONFIGURE_REPO_ATTRS = _gen_bootstrap_repo_attrs()

def _new_platform_bootstrap_configure_ctx(os, arch):
    packages_port_patches = {}
    packages_drop_features = {}

    def match_platform(compare_os, compare_arch, is_exact_match):
        if match_platform:
            return os == compare_os and arch == compare_arch

        return (os == "*" or os == compare_os) and (arch == "*" or arch == compare_arch)

    def add_config(config):
        for patch in configure.port_patches:
            packages_port_patches[patch] = config.package

        add_or_extend_list_in_dict(
            packages_drop_features,
            config.package,
            config.drop_features,
        )

    def fill_from_repo_ctx(rctx):
        name_prefix = _repo_attr_prefix_for(os, arch)
        packages_port_patches.update(getattr(rctx.attr, "%spackages_port_patches" % name_prefix).items())
        packages_drop_features.update(getattr(rctx.attr, "%spackages_drop_features" % name_prefix).items())

    def to_repo_attrs():
        name_prefix = _repo_attr_prefix_for(os, arch)
        return {
            "%spackages_port_patches" % name_prefix: packages_port_patches,
            "%spackages_drop_features" % name_prefix: packages_drop_features,
        }

    return struct(
        os = os,
        arch = arch,
        packages_port_patches = packages_port_patches,
        packages_drop_features = packages_drop_features,
        match_platform = match_platform,
        add_config = add_config,
        fill_from_repo_ctx = fill_from_repo_ctx,
        to_repo_attrs = to_repo_attrs,
    )

def new_bootstrap_configure_ctx():
    contexts = [
        _new_platform_bootstrap_configure_ctx(os, arch)
        for os, arch in PLATFORMS_PAIRS
    ]

    def add_config(config):
        for context in contexts:
            if context.match_platform(config.os, config.arch, True):
                context.add_config(config)
                return

        fail("Unknown configure os - '%s' or arch - '%s'" % (
            config.os,
            config.arch,
        ))

    def fill_from_repo_ctx(rctx):
        for context in contexts:
            context.fill_from_repo_ctx(rctx)

    def to_repo_attrs():
        result = {}
        for context in contexts:
            result |= context.to_repo_attrs()
        return result

    def packages_port_patches(os, arch):
        result = {}
        for context in contexts:
            if not context.match_platform(os, arch, False):
                continue

            result |= context.packages_port_patches

        return result

    def packages_drop_features(os, arch):
        result = {}
        for context in contexts:
            if not context.match_platform(os, arch, False):
                continue

            result |= context.packages_drop_features

        return result

    return struct(
        add_config = add_config,
        fill_from_repo_ctx = fill_from_repo_ctx,
        to_repo_attrs = to_repo_attrs,
        packages_port_patches = packages_port_patches,
        packages_drop_features = packages_drop_features,
    )
