load("@bazel_skylib//lib:paths.bzl", "paths")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "VcpkgPlatformTrippletProvider")

VcpkgPackageInfo = provider(
    doc = "Vcpkg package information",
    fields = [
        "name",
        "port",
        "buildtree",
    ],
)

VcpkgPackageDepsInfo = provider(
    doc = "Vcpkg package dependencies",
    fields = [
        "deps",
    ],
)

def _vcpkg_build_impl(ctx):
    vcpkg_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"].vcpkg_info

    cmake_data = vcpkg_info.cmake_files.files.to_list()

    cmake_bin = "/".join(cmake_data[0].path.split("/")[0:2] + ["bin"])

    deps_info = VcpkgPackageDepsInfo(
        deps = depset(transitive = [
            dep[VcpkgPackageDepsInfo].deps
            for dep in ctx.attr.deps
        ]),
    )

    package_info = VcpkgPackageInfo(
        name = ctx.attr.name,
        port = ctx.files.port,
        buildtree = ctx.files.buildtree,
    )

    triplet = ctx.attr._tripplet[VcpkgPlatformTrippletProvider].triplet
    install_dir = ctx.actions.declare_directory("%s/install" % ctx.attr.name)

    ctx.actions.run(
        inputs = [
            vcpkg_info.vcpkg_manifest,
        ],
        outputs = [
            install_dir,
        ],
        executable = ctx.executable._prepare_install_dir,
        arguments = [
            install_dir.path,
            triplet,
            vcpkg_info.vcpkg_manifest.path,
        ],
    )

    package_output_dir = ctx.actions.declare_directory("{name}/packages/{name}_{triplet}".format(
        name = ctx.attr.name,
        triplet = triplet,
    ))

    inputs = vcpkg_info.vcpkg_files.files.to_list() + cmake_data + [
        vcpkg_info.vcpkg_manifest,
        install_dir,
    ]

    for dep_info in [dep[VcpkgPackageInfo] for dep in deps_info.deps.to_list()] + [package_info]:
        inputs += dep_info.buildtree
        inputs += dep_info.port

    vcpkg_root = "%s/vcpkg" % paths.dirname(vcpkg_info.vcpkg_tool.path)

    # print("vcpkg root: %s" % vcpkg_root)
    packages_dir = paths.dirname(package_output_dir.path)
    # print("packages dir: %s" % packages_dir)

    ctx.actions.run(
        tools = [
            vcpkg_info.vcpkg_tool,
        ],
        inputs = inputs,
        outputs = [
            package_output_dir,
        ],
        executable = vcpkg_info.vcpkg_tool,
        arguments = [
            "build",
            ctx.attr.name,
            "--vcpkg-root=%s" % vcpkg_root,
            "--x-buildtrees-root=%s/buildtrees" % vcpkg_root,
            "--downloads-root=downloads=%s/downloads" % vcpkg_root,
            "--x-install-root=%s" % install_dir.path,
            "--x-packages-root=%s" % packages_dir,
        ],
        env = {
            "CMAKE_BIN": cmake_bin,
            "VCPKG_MAX_CONCURRENCY": "1",
            "VCPKG_DEBUG": "1",
        },
    )

    return [
        DefaultInfo(files = depset([
            install_dir,
            package_output_dir,
        ])),
        package_info,
        deps_info,
    ]

vcpkg_build = rule(
    implementation = _vcpkg_build_impl,
    attrs = {
        "port": attr.label(allow_files = True),
        "buildtree": attr.label(allow_files = True),
        "deps": attr.label_list(providers = [
            VcpkgPackageInfo,
            VcpkgPackageDepsInfo,
        ]),
        "_tripplet": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:vcpkg_triplet",
            doc = "Vcpkg triplet",
        ),
        "_prepare_install_dir": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:prepare_install_dir",
            executable = True,
            cfg = "exec",
            doc = "Vcpkg install directory",
        ),
    },
    toolchains = [
        "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
    ],
)

def _vcpkg_package_link_transition_impl(settings, attr):
    _ignore = (settings, attr)
    return {
        "//command_line_option:compilation_mode": "fastbuild",
    }

vcpkg_package_link_transition = transition(
    implementation = _vcpkg_package_link_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ],
)

def _vcpkg_package_link_impl(ctx):
    return ctx.attr.package[0][DefaultInfo]

vcpkg_package_link = rule(
    implementation = _vcpkg_package_link_impl,
    attrs = {
        "package": attr.label(
            mandatory = True,
            # Call to `vcpkg build` produce both debug and release artifacts.
            # Lets use this transition hack to not to break cacheability
            # when `-c opt` or `-c dbg` command line options are used.
            # Our transition will override the compilation mode to fastbuild,
            # and have same output paths.
            cfg = vcpkg_package_link_transition,
            doc = "Package to link",
        ),
    },
)

_BAZEL_PACKAGE_TPL = """\
load("@rules_vcpkg//vcpkg:vcpkg.bzl", "vcpkg_package_link")

vcpkg_package_link(
    name = "{package}",
    package = "@vcpkg//:{package}",
    visibility = ["//visibility:public"],
)
"""

def _vcpkg_package_impl(rctx):
    rctx.file(
        "BUILD.bazel",
        _BAZEL_PACKAGE_TPL.format(
            package = rctx.attr.package,
        ),
    )

vcpkg_package = repository_rule(
    implementation = _vcpkg_package_impl,
    attrs = {
        "package": attr.string(doc = "Package name"),
    },
)
