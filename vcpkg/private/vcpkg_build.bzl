load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

VcpkgBuiltPackageInfo = provider(
    doc = "Vcpkg built package info",
    fields = [
        "name",
        "port",
        "output",
        "downloads",
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

def _commonprefix(m):
    if not m:
        return ""
    s1 = min(m)
    s2 = max(m)
    for i in range(len(s1)):
        if s1[i] != s2[i]:
            return s1[:i]
    return s1

def _vcpkg_build_impl(ctx):
    vcpkg_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"].vcpkg_info
    vcpkg_current_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:current_toolchain_type"].vcpkg_current_info
    vcpkg_external_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:external_toolchain_type"].vcpkg_external_info

    current_binaries = vcpkg_current_info.binaries.to_list()
    external_binaries = vcpkg_external_info.binaries.to_list()
    external_transitive = vcpkg_external_info.transitive.to_list()

    cur_bin_dir = paths.dirname(current_binaries[0].path)
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

    deps_downloads = [
        dep_info.downloads
        for dep_info in deps_list
    ]

    overlay_triplets = vcpkg_current_info.overlay_triplets.to_list()

    inputs = [packages_list_file] + [
        item
        for sublist in [
            ctx.files.port,
            ctx.files.buildtree,
            ctx.files.downloads,
            current_binaries,
            vcpkg_info.vcpkg_files.files.to_list(),
            vcpkg_current_info.transitive.to_list(),
            overlay_triplets,
            external_binaries,
            external_transitive,
            deps_outputs,
        ] + deps_downloads + deps_ports
        for item in sublist
    ]

    vcpkg_root = "%s/vcpkg" % paths.dirname(vcpkg_info.vcpkg_tool.path)

    package_output_dir_path = "packages/{name}_{triplet}".format(
        name = ctx.attr.package_name,
        triplet = vcpkg_current_info.triplet,
    )

    package_output_dir = ctx.actions.declare_directory(package_output_dir_path)

    call_vcpkg_wrapper = ctx.actions.declare_file("call_vcpkg_%s.sh" % ctx.attr.name)

    if ctx.attr.package_features:
        build_target_name = "%s[%s]" % (
            ctx.attr.package_name,
            ",".join(ctx.attr.package_features),
        )
    else:
        build_target_name = ctx.attr.package_name

    ctx.actions.expand_template(
        template = ctx.file._call_vcpkg_wrapper_tpl,
        output = call_vcpkg_wrapper,
        is_executable = True,
        substitutions = {
            "__bin_dir__": bin_dir,
            "__cur_bin_dir__": cur_bin_dir,
            "__vcpkg_bin__": vcpkg_info.vcpkg_tool.path,
            "__prepare_install_dir_bin__": ctx.executable._prepare_install_dir.path,
            "__packages_list_file__": packages_list_file.path,
            "__package_name__": ctx.attr.package_name,
            "__build_target_name__": build_target_name,
            "__vcpkg_root__": vcpkg_root,
            "__buildtrees_root__": "%s/buildtrees" % vcpkg_root,
            "__downloads_root__": "%s/downloads" % vcpkg_root,
            "__package_output_dir__": paths.dirname(package_output_dir.path),
            "__package_output_basename__": paths.basename(package_output_dir.path),
            # "__cxx_compiler__": vcpkg_current_info.cxx_compiler_str,
            "__overlay_tripplets__": _commonprefix([
                ot.path
                for ot in overlay_triplets
            ]),
        },
    )

    cpus = _unwrap_cpus_count(
        ctx.attr.cpus,
        vcpkg_info.host_cpu_count,
    )

    is_debug = ctx.attr._debug[BuildSettingInfo].value
    is_debug_reuse_outputs = ctx.attr._debug_reuse_outputs[BuildSettingInfo].value

    ctx.actions.run(
        tools = [
            vcpkg_info.vcpkg_tool,
            call_vcpkg_wrapper,
            ctx.executable._prepare_install_dir,
        ],
        inputs = inputs,
        outputs = [package_output_dir],
        executable = call_vcpkg_wrapper,
        env = {
            "VCPKG_MAX_CONCURRENCY": cpus,
            "VCPKG_DEBUG": str(int(is_debug)),
            "VCPKG_DEBUG_REUSE_OUTPUTS": str(int(is_debug and is_debug_reuse_outputs)),
        },
        execution_requirements = {
            "resources:cpu:%s" % cpus: "",
        },
    )

    return [
        DefaultInfo(files = depset([
            package_output_dir,
        ])),
        VcpkgBuiltPackageInfo(
            name = ctx.attr.package_name,
            port = ctx.files.port,
            output = package_output_dir,
            downloads = ctx.files.downloads,
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
        "package_features": attr.string_list(),
        "deps": attr.label_list(providers = [
            VcpkgBuiltPackageInfo,
            VcpkgPackageDepsInfo,
        ]),
        "cpus": attr.string(
            mandatory = True,
            doc = "Cpu cores to use for package build, accept `HOST_CPUS` keyword",
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
        "_debug": attr.label(
            providers = [BuildSettingInfo],
            default = "//:debug",
        ),
        "_debug_reuse_outputs": attr.label(
            providers = [BuildSettingInfo],
            default = "//:debug_reuse_outputs",
        ),
    },
    toolchains = [
        "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
        "@rules_vcpkg//vcpkg/toolchain:current_toolchain_type",
        "@rules_vcpkg//vcpkg/toolchain:external_toolchain_type",
    ],
)
