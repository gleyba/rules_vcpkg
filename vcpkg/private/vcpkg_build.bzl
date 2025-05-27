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

def _unwrap_cpus_count(cpus, host_cpus):
    if cpus == "HOST_CPUS":
        return str(host_cpus)
    return cpus

def _vcpkg_build_impl(ctx):
    vcpkg_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"].vcpkg_info

    vcpkg_external_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:external_toolchain_type"].vcpkg_external_info

    external_binaries = vcpkg_external_info.binaries.to_list()
    external_transitive = vcpkg_external_info.transitive.to_list()

    bin_dir = paths.dirname(external_binaries[0].path)

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

    packages_list_file = ctx.actions.declare_file("%s_packages.list" % ctx.attr.name)

    ctx.actions.write(
        output = packages_list_file,
        content = "\n".join(sorted([
            deps_output.path
            for deps_output in deps_outputs
        ])),
    )

    deps_ports = [
        dep_info.port
        for dep_info in deps_list
    ]

    inputs = [packages_list_file] + [
        item
        for sublist in [
            ctx.files.port,
            ctx.files.buildtree,
            ctx.files.downloads,
            vcpkg_info.vcpkg_files.files.to_list(),
            external_binaries,
            external_transitive,
            deps_outputs,
        ] + deps_ports
        for item in sublist
    ]

    vcpkg_root = "%s/vcpkg" % paths.dirname(vcpkg_info.vcpkg_tool.path)

    package_output_dir_path = "{name}/packages/{name}_{triplet}".format(
        name = ctx.attr.package_name,
        triplet = ctx.attr._tripplet[VcpkgPlatformTrippletProvider].triplet,
    )

    package_output_dir = ctx.actions.declare_directory(package_output_dir_path)

    call_vcpkg_wrapper = ctx.actions.declare_file("call_vcpkg_%s.sh" % ctx.attr.name)
    ctx.actions.expand_template(
        template = ctx.file._call_vcpkg_wrapper_tpl,
        output = call_vcpkg_wrapper,
        is_executable = True,
        substitutions = {
            "__bin_dir__": bin_dir,
            "__vcpkg_bin__": vcpkg_info.vcpkg_tool.path,
            "__prepare_install_dir_bin__": ctx.executable._prepare_install_dir.path,
            "__install_dir_path__": install_dir.path,
            "__packages_list_file__": packages_list_file.path,
            "__package_name__": ctx.attr.package_name,
            "__vcpkg_root__": vcpkg_root,
            "__buildtrees_root__": "%s/buildtrees" % vcpkg_root,
            "__downloads_root__": "%s/downloads" % vcpkg_root,
            "__install_root__": install_dir.path,
            "__packages_root__": paths.dirname(package_output_dir.path),
        },
    )

    cpus = _unwrap_cpus_count(
        ctx.attr.cpus,
        vcpkg_info.host_cpu_count,
    )
    ctx.actions.run(
        tools = [
            vcpkg_info.vcpkg_tool,
            call_vcpkg_wrapper,
            ctx.executable._prepare_install_dir,
        ],
        inputs = inputs,
        outputs = [
            install_dir,
            package_output_dir,
        ],
        executable = call_vcpkg_wrapper,
        env = {
            "VCPKG_MAX_CONCURRENCY": cpus,
            "VCPKG_DEBUG": "1",
        },
        execution_requirements = {
            "resources:cpu:%s" % cpus: "",
        },
    )

    return [
        DefaultInfo(files = depset([
            install_dir,
            package_output_dir,
        ])),
        VcpkgBuiltPackageInfo(
            name = ctx.attr.package_name,
            port = ctx.files.port,
            output = package_output_dir,
        ),
        deps_info,
    ]

vcpkg_build = rule(
    implementation = _vcpkg_build_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "port": attr.label(allow_files = True),
        "buildtree": attr.label(allow_files = True),
        "downloads": attr.label(allow_files = True),
        "deps": attr.label_list(providers = [
            VcpkgBuiltPackageInfo,
            VcpkgPackageDepsInfo,
        ]),
        "cpus": attr.string(
            mandatory = True,
            doc = "Cpu cores to use for package build, accept `HOST_CPUS` keyword",
        ),
        "_tripplet": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:vcpkg_triplet",
            doc = "Vcpkg triplet",
        ),
        "_call_vcpkg_wrapper_tpl": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:call_vcpkg_wrapper_tpl",
            allow_single_file = True,
            doc = "Vcpkg wrapper script template",
        ),
        "_prepare_install_dir": attr.label(
            default = "@rules_vcpkg//vcpkg/vcpkg_utils:prepare_install_dir",
            executable = True,
            cfg = "exec",
            doc = "Tool to prepare vcpkg install directory structure",
        ),
    },
    toolchains = [
        "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
        "@rules_vcpkg//vcpkg/toolchain:external_toolchain_type",
    ],
)
