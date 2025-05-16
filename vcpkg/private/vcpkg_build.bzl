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

    inputs = [
        vcpkg_info.vcpkg_manifest,
    ] + [
        item
        for sublist in [
            ctx.files.port,
            ctx.files.buildtree,
            ctx.files.downloads,
            vcpkg_info.vcpkg_files.files.to_list(),
            cmake_data,
            deps_outputs,
        ] + deps_ports
        for item in sublist
    ]

    vcpkg_root = "%s/vcpkg" % paths.dirname(vcpkg_info.vcpkg_tool.path)

    package_output_dir_path = "{name}/packages/{name}_{triplet}".format(
        name = ctx.attr.name,
        triplet = ctx.attr._tripplet[VcpkgPlatformTrippletProvider].triplet,
    )

    package_output_dir = ctx.actions.declare_directory(package_output_dir_path)

    args = ctx.actions.args()
    args.add(install_dir.path)
    args.add(vcpkg_info.vcpkg_manifest)
    for dep_output in deps_outputs:
        args.add(dep_output.path)

    args.add("--")

    args.add("build")
    args.add(ctx.attr.name)
    args.add("--vcpkg-root=%s" % vcpkg_root)
    args.add("--x-buildtrees-root=%s/buildtrees" % vcpkg_root)
    args.add("--downloads-root=%s/downloads" % vcpkg_root)
    args.add("--x-install-root=%s" % install_dir.path)
    args.add("--x-packages-root=%s" % paths.dirname(package_output_dir.path))

    ctx.actions.run(
        tools = [
            vcpkg_info.vcpkg_tool,
            ctx.executable._call_vcpkg_wrapper,
            ctx.executable._prepare_install_dir,
        ],
        inputs = inputs,
        outputs = [
            install_dir,
            package_output_dir,
        ],
        executable = ctx.executable._call_vcpkg_wrapper,
        arguments = [args],
        env = {
            "CMAKE_BIN": cmake_bin,
            "VCPKG_BIN": vcpkg_info.vcpkg_tool.path,
            "WORK_DIR": paths.dirname(vcpkg_info.vcpkg_manifest.path),
            "PREPARE_INSTALL_DIR_BIN": ctx.executable._prepare_install_dir.path,
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
        "downloads": attr.label(allow_files = True),
        "deps": attr.label_list(providers = [
            VcpkgBuiltPackageInfo,
            VcpkgPackageDepsInfo,
        ]),
        "_tripplet": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:vcpkg_triplet",
            doc = "Vcpkg triplet",
        ),
        "_call_vcpkg_wrapper": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:call_vcpkg_wrapper",
            executable = True,
            cfg = "exec",
            doc = "Vcpkg wrapper script",
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
