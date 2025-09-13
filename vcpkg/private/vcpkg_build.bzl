load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_pkg//pkg:providers.bzl", "PackageFilesInfo")

VcpkgBuiltPackageInfo = provider(
    doc = "Vcpkg built package info",
    fields = [
        "name",
        "port_files",
        "outputs",
        "downloads",
    ],
)

VcpkgPackageDepsInfo = provider(
    doc = "Vcpkg package dependencies",
    fields = [
        "deps",
    ],
)

_INT_TYPE = type(42)
_STR_TYPE = type("42")
_LIST_TYPE = type(["42"])

def unwrap_cpus_count(cpus, host_cpus):
    if type(cpus) == _INT_TYPE:
        return cpus
    elif type(cpus) == _STR_TYPE:
        if cpus.isdigit():
            return int(cpus)
        elif cpus == "HOST_CPUS":
            return host_cpus
        elif cpus.startswith("HOST_CPUS/"):
            return host_cpus / int(cpus[10:])

    fail("Can't substitute CPU count: %s" % cpus)

def _commonprefix(m):
    if not m:
        return ""
    s1 = min(m)
    s2 = max(m)
    for i in range(len(s1)):
        if s1[i] != s2[i]:
            return s1[:i]
    return s1

def _process_debug(ctx, build_ctx):
    is_debug = ctx.attr._debug[BuildSettingInfo].value
    is_debug_reuse_outputs = ctx.attr._debug_reuse_outputs[BuildSettingInfo].value
    build_ctx.exports["VCPKG_DEBUG"] = str(int(is_debug))
    build_ctx.exports["VCPKG_DEBUG_REUSE_OUTPUTS"] = str(int(is_debug and is_debug_reuse_outputs))
    build_ctx.prepare_install_dir_cfg["reuse_outputs"] = is_debug_reuse_outputs

def _process_package(ctx, build_ctx):
    build_ctx.add_inputs(ctx.files.buildtree)
    build_ctx.add_inputs(ctx.files.downloads)
    build_ctx.substitutions["__package_name__"] = ctx.attr.package_name
    if ctx.attr.override_sources:
        build_ctx.prepare_install_dir_cfg["override_sources"] = ctx.attr.override_sources

    if ctx.attr.package_features:
        build_target_name = "%s[%s]" % (
            ctx.attr.package_name,
            ",".join(ctx.attr.package_features),
        )
    else:
        build_target_name = ctx.attr.package_name

    build_ctx.substitutions["__build_target_name__"] = build_target_name

def _process_port(ctx, build_ctx):
    port = ctx.attr.port[DirectoryInfo]
    build_ctx.validate_package_output_cfg["port_root"] = port.path
    build_ctx.add_inputs(port.transitive_files.to_list())

def _process_external_binaries(ctx, build_ctx):
    external_binaries = ctx.attr._external_bins[DirectoryInfo]
    build_ctx.add_inputs(external_binaries.transitive_files.to_list())
    bin_dir = external_binaries.path
    build_ctx.exports["PATH"] = "${PWD}/%s" % bin_dir
    build_ctx.exports["M4"] = "${PWD}/%s/m4" % bin_dir

def _process_externals(ctx, build_ctx):
    external_transitive = ctx.attr._externals[DefaultInfo]
    build_ctx.add_inputs(external_transitive.files.to_list())

def _process_vcpkg_current_info(ctx, build_ctx):
    vcpkg_current_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:current_toolchain_type"].vcpkg_current_info
    build_ctx.add_inputs(vcpkg_current_info.transitive.to_list())
    build_ctx.exports["CC"] = vcpkg_current_info.cc_compiler
    build_ctx.exports["CXX"] = vcpkg_current_info.cxx_compiler

    overlay_triplets = vcpkg_current_info.overlay_triplets.to_list()
    build_ctx.add_inputs(overlay_triplets)

    overlay_triplets_dir = _commonprefix([
        ot.path
        for ot in overlay_triplets
    ])

    build_ctx.substitutions["__overlay_tripplets__"] = overlay_triplets_dir
    build_ctx.exports["VCPKG_OVERLAY_TRIPLETS"] = "${VCPKG_EXEC_ROOT}/%s" % overlay_triplets_dir

    package_output_dir_path = "packages/{name}_{triplet}".format(
        name = ctx.attr.package_name,
        triplet = vcpkg_current_info.triplet,
    )
    package_output_dir = ctx.actions.declare_directory(package_output_dir_path)
    build_ctx.outputs.append(package_output_dir)
    build_ctx.substitutions["__package_output_dir__"] = paths.dirname(package_output_dir.path)
    build_ctx.substitutions["__package_output_basename__"] = paths.basename(package_output_dir.path)

def _process_vcpkg_info(ctx, build_ctx):
    vcpkg_info = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"].vcpkg_info
    build_ctx.add_inputs(vcpkg_info.vcpkg_files.files.to_list())
    build_ctx.substitutions["__vcpkg_bin__"] = vcpkg_info.vcpkg_tool.path
    build_ctx.tools.append(vcpkg_info.vcpkg_tool)

    vcpkg_repo_root = paths.dirname(vcpkg_info.vcpkg_tool.path)
    vcpkg_root = "%s/vcpkg" % vcpkg_repo_root

    build_ctx.substitutions["__vcpkg_root__"] = vcpkg_root
    build_ctx.exports["VCPKG_ROOT"] = "${VCPKG_EXEC_ROOT}/%s" % vcpkg_root
    build_ctx.prepare_install_dir_cfg["buildtrees_root"] = "%s/buildtrees" % vcpkg_root
    build_ctx.prepare_install_dir_cfg["downloads_root"] = "%s/downloads" % vcpkg_repo_root

    assets = ctx.attr.assets[DirectoryInfo]
    build_ctx.add_inputs(assets.transitive_files.to_list())
    build_ctx.substitutions["__assets__"] = "%s/assets" % vcpkg_repo_root

def _process_flags(ctx, build_ctx):
    build_ctx.exports["ADDITIONAL_CFLAGS"] = "%s" % " ".join(ctx.attr.cflags)
    build_ctx.exports["ADDITIONAL_LINKER_FLAGS"] = "%s" % " ".join(ctx.attr.linkerflags)

def _process_overlay_sources(ctx, build_ctx):
    overlay_sources = {}
    for overlay_src in ctx.attr.overlay_sources:
        pkg_files_info = overlay_src[PackageFilesInfo]
        for dest, src in pkg_files_info.dest_src_map.items():
            overlay_sources[dest] = src.path
            build_ctx.inputs.append(src)

    build_ctx.prepare_install_dir_cfg["overlay_sources"] = overlay_sources

def _process_deps(ctx, build_ctx):
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
        dep_info.outputs
        for dep_info in deps_list
    ]

    build_ctx.add_inputs(deps_outputs)

    deps_ports = [
        dep_info.port_files
        for dep_info in deps_list
    ]

    build_ctx.add_inputs([f for f in deps_ports])

    deps_downloads = [
        dep_info.downloads
        for dep_info in deps_list
    ]

    build_ctx.add_inputs([d for d in deps_downloads])

    packages_list_file = ctx.actions.declare_file("%s_packages.list" % ctx.attr.name)

    ctx.actions.write(
        output = packages_list_file,
        content = "\n".join(sorted([
            output.path
            for outputs in deps_outputs
            for output in outputs
        ])),
    )

    build_ctx.inputs.append(packages_list_file)
    build_ctx.prepare_install_dir_cfg["packages_list_file"] = packages_list_file.path

    return deps_info

def _process_prepare_install_dir_bin(ctx, build_ctx):
    build_ctx.tools.append(ctx.executable._prepare_install_dir)
    build_ctx.substitutions["__prepare_install_dir_bin__"] = ctx.executable._prepare_install_dir.path

    prepare_install_dir_cfg = ctx.actions.declare_file("%s_prepare_install_dir_cfg.json" % ctx.attr.name)
    ctx.actions.write(
        output = prepare_install_dir_cfg,
        content = json.encode_indent(build_ctx.prepare_install_dir_cfg),
    )
    build_ctx.inputs.append(prepare_install_dir_cfg)
    build_ctx.substitutions["__prepare_install_dir_cfg__"] = prepare_install_dir_cfg.path

def _process_validate_package_output_bin(ctx, build_ctx):
    build_ctx.tools.append(ctx.executable._validate_package_output)
    build_ctx.substitutions["__validate_package_output_bin__"] = ctx.executable._validate_package_output.path

    validate_package_output_cfg = ctx.actions.declare_file("%s_validate_package_output_cfg.json" % ctx.attr.name)
    ctx.actions.write(
        output = validate_package_output_cfg,
        content = json.encode_indent(build_ctx.validate_package_output_cfg),
    )
    build_ctx.inputs.append(validate_package_output_cfg)
    build_ctx.substitutions["__validate_package_output_cfg__"] = validate_package_output_cfg.path

def _vcpkg_build_impl(ctx, cpus, resource_set, execution_requirements):
    build_ctx_inputs = []

    def add_inputs(inputs):
        for input in inputs:
            if type(input) == _LIST_TYPE:
                build_ctx_inputs.extend(input)
            else:
                build_ctx_inputs.append(input)

    build_ctx = struct(
        inputs = build_ctx_inputs,
        add_inputs = add_inputs,
        outputs = [],
        tools = [],
        exports = {
            "HOME": "/tmp/home",
            "VCPKG_EXEC_ROOT": "${PWD}",
            "VCPKG_MAX_CONCURRENCY": str(cpus),
        },
        substitutions = {},
        prepare_install_dir_cfg = {},
        validate_package_output_cfg = {},
    )

    _process_debug(ctx, build_ctx)
    _process_package(ctx, build_ctx)
    _process_port(ctx, build_ctx)
    _process_external_binaries(ctx, build_ctx)
    _process_externals(ctx, build_ctx)
    _process_vcpkg_current_info(ctx, build_ctx)
    _process_vcpkg_info(ctx, build_ctx)
    _process_flags(ctx, build_ctx)
    _process_overlay_sources(ctx, build_ctx)
    deps_info = _process_deps(ctx, build_ctx)
    _process_prepare_install_dir_bin(ctx, build_ctx)
    _process_validate_package_output_bin(ctx, build_ctx)

    call_vcpkg_wrapper = ctx.actions.declare_file("call_vcpkg_%s.sh" % ctx.attr.name)

    ctx.actions.expand_template(
        template = ctx.file._call_vcpkg_wrapper_tpl,
        output = call_vcpkg_wrapper,
        is_executable = True,
        substitutions = {
            "__exports__": "\n".join([
                "export %s=\"%s\"" % item
                for item in build_ctx.exports.items()
            ]),
        } | build_ctx.substitutions,
    )

    ctx.actions.run(
        tools = build_ctx.tools,
        inputs = build_ctx.inputs,
        outputs = build_ctx.outputs,
        executable = call_vcpkg_wrapper,
        execution_requirements = execution_requirements,
        resource_set = resource_set,
        mnemonic = "VCPKGBuild",
    )

    return [
        DefaultInfo(files = depset(build_ctx.outputs)),
        VcpkgBuiltPackageInfo(
            name = ctx.attr.package_name,
            port_files = ctx.files.port,
            outputs = build_ctx.outputs,
            downloads = ctx.files.downloads,
        ),
        deps_info,
    ]

def vcpkg_build(cpus, resource_set, execution_requirements):
    return rule(
        implementation = lambda rctx: _vcpkg_build_impl(
            rctx,
            cpus,
            resource_set,
            execution_requirements,
        ),
        attrs = {
            "package_name": attr.string(mandatory = True),
            "port": attr.label(providers = [DirectoryInfo]),
            "buildtree": attr.label(allow_files = True),
            "downloads": attr.label(allow_files = True),
            "assets": attr.label(providers = [DirectoryInfo]),
            "package_features": attr.string_list(),
            "deps": attr.label_list(providers = [
                VcpkgBuiltPackageInfo,
                VcpkgPackageDepsInfo,
            ]),
            "cflags": attr.string_list(
                mandatory = False,
                doc = "Additional c flags to propagate to build, are not transitive",
            ),
            "linkerflags": attr.string_list(
                mandatory = False,
                doc = "Additional linker flags to propagate to build, are not transitive",
            ),
            "override_sources": attr.string(
                mandatory = False,
                doc = "Override sources location, useful for debug",
            ),
            "overlay_sources": attr.label_list(
                mandatory = False,
                providers = [PackageFilesInfo],
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
            "_validate_package_output": attr.label(
                default = "@rules_vcpkg//vcpkg/vcpkg_utils:validate_package_output",
                executable = True,
                cfg = "exec",
                doc = "Tool to validate vcpkg package output directory",
            ),
            "_debug": attr.label(
                providers = [BuildSettingInfo],
                default = "//:debug",
            ),
            "_debug_reuse_outputs": attr.label(
                providers = [BuildSettingInfo],
                default = "//:debug_reuse_outputs",
            ),
            "_externals": attr.label(
                providers = [DefaultInfo],
                default = "@vcpkg_external//:root",
            ),
            "_external_bins": attr.label(
                providers = [DirectoryInfo],
                default = "@vcpkg_external//bin",
            ),
        },
        toolchains = [
            "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
            "@rules_vcpkg//vcpkg/toolchain:current_toolchain_type",
        ],
    )
