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

VcpkgBuiltPackageInfo = provider(
    doc = "Vcpkg built package info",
    fields = [
        "name",
        "port",
        "output",
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
        deps = depset(
            [
                dep[VcpkgBuiltPackageInfo]
                for dep in ctx.attr.deps
            ],
            transitive = [
                dep[VcpkgPackageDepsInfo].deps
                for dep in ctx.attr.deps
            ],
        ),
    )

    install_dir = ctx.actions.declare_directory("%s/install" % ctx.attr.name)

    deps_list = deps_info.deps.to_list()
    deps_outputs = [
        dep_info.output
        for dep_info in deps_list
    ]
    deps_ports = [
        dep_info.port
        for dep_info in deps_list
    ]

    prepare_install_dir_args = ctx.actions.args()
    prepare_install_dir_args.add(install_dir.path)
    prepare_install_dir_args.add(vcpkg_info.vcpkg_manifest)
    for dep_output in deps_outputs:
        prepare_install_dir_args.add(dep_output.path)

    ctx.actions.run(
        inputs = [
            vcpkg_info.vcpkg_manifest,
        ] + deps_outputs,
        outputs = [
            install_dir,
        ],
        executable = ctx.executable._prepare_install_dir,
        arguments = [prepare_install_dir_args],
    )

    inputs = [
        vcpkg_info.vcpkg_manifest,
        install_dir,
    ] + [
        item
        for sublist in [
            ctx.files.port,
            ctx.files.buildtree,
            vcpkg_info.vcpkg_files.files.to_list(),
            cmake_data,
            deps_outputs,
        ] + deps_ports
        for item in sublist
    ]

    vcpkg_root = "%s/vcpkg" % paths.dirname(vcpkg_info.vcpkg_tool.path)

    package_output_dir = ctx.actions.declare_directory("{name}/packages/{name}_{triplet}".format(
        name = ctx.attr.name,
        triplet = ctx.attr._tripplet[VcpkgPlatformTrippletProvider].triplet,
    ))

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
            "--downloads-root=%s/downloads" % vcpkg_root,
            "--x-install-root=%s" % install_dir.path,
            "--x-packages-root=%s" % paths.dirname(package_output_dir.path),
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
        VcpkgBuiltPackageInfo(
            name = ctx.attr.name,
            port = ctx.files.port,
            output = package_output_dir,
        ),
        deps_info,
    ]

vcpkg_build = rule(
    implementation = _vcpkg_build_impl,
    attrs = {
        "port": attr.label(allow_files = True),
        "buildtree": attr.label(allow_files = True),
        "deps": attr.label_list(providers = [
            VcpkgBuiltPackageInfo,
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
    package = ctx.attr.package[0]

    # print(package[VcpkgPackageInfo].output_dir.path)
    # print(package[VcpkgPackageInfo].output_dir.is_directory)
    return package[DefaultInfo]

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
