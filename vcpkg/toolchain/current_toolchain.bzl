load("@bazel_skylib//lib:paths.bzl", "paths")
load("@cc_toolchain_util.bzl", "get_tools_info")
load("//vcpkg/toolchain/private:vcpkg_cc_info.bzl", "VcpkgCCInfo")
load("//vcpkg/vcpkg_utils:format_utils.bzl", "format_additions")

VcpgCurrentInfo = provider(
    doc = "Information about current binaries from registered toolchains used with vcpkg.",
    fields = [
        "binaries",
        "transitive",
        "triplet",
        "overlay_triplets",
        "overlay_tripplets_debug",
        "cc_compiler",
        "cxx_compiler",
    ],
)

def _resolve_tool_path(tool_path):
    if paths.is_absolute(tool_path):
        return tool_path
    else:
        return "${VCPKG_EXEC_ROOT}/%s" % tool_path

def _create_overlay_tripplets(ctx, build_type, additional_sets):
    triplet_cmake = ctx.actions.declare_file("overlay_triplets_%s/%s.cmake" % (build_type, ctx.attr.triplet))
    toolchain_cmake = ctx.actions.declare_file("overlay_triplets_%s/toolchain.cmake" % build_type)

    additional_sets |= {
        "VCPKG_BUILD_TYPE": build_type,
        "VCPKG_CHAINLOAD_TOOLCHAIN_FILE": "\"$ENV{VCPKG_EXEC_ROOT}/%s\"" % toolchain_cmake.path,
    }

    vcpkg_cc_info = ctx.attr._vcpkg_cc_info[VcpkgCCInfo]

    flags_substitutions = {
        "%%BUILD_TYPE%%": build_type,
        "%%C_COMPILER%%": vcpkg_cc_info.cc,
        "%%CXX_COMPILER%%": vcpkg_cc_info.cxx,
        "%%AR%%": vcpkg_cc_info.ar,
        "%%C_FLAGS%%": vcpkg_cc_info.cc_flags,
        "%%CXX_FLAGS%%": vcpkg_cc_info.cxx_flags,
        "%%LINKER_FLAGS%%": vcpkg_cc_info.linker_flags,
        "%%C_FLAGS_DEBUG%%": vcpkg_cc_info.dbg_cc_flags,
        "%%CXX_FLAGS_DEBUG%%": vcpkg_cc_info.dbg_cxx_flags,
        "%%C_FLAGS_RELEASE%%": vcpkg_cc_info.opt_cc_flags,
        "%%CXX_FLAGS_RELEASE%%": vcpkg_cc_info.opt_cxx_flags,
        "%%LINKER_FLAGS_DEBUG%%": vcpkg_cc_info.dbg_cxx_linker_shared,
        "%%EXE_LINKER_FLAGS_DEBUG%%": vcpkg_cc_info.dbg_cxx_linker_executable,
        "%%LINKER_FLAGS_RELEASE%%": vcpkg_cc_info.opt_cxx_linker_shared,
        "%%EXE_LINKER_FLAGS_RELEASE%%": vcpkg_cc_info.opt_cxx_linker_executable,
    }

    ctx.actions.expand_template(
        template = ctx.file.triplet_template,
        output = triplet_cmake,
        substitutions = (
            ctx.attr.substitutions |
            flags_substitutions |
            format_additions({}, additional_sets)
        ),
    )

    ctx.actions.expand_template(
        template = ctx.file.toolchain_template,
        output = toolchain_cmake,
        substitutions = (
            ctx.attr.substitutions |
            flags_substitutions
        ),
    )

    return [
        triplet_cmake,
        toolchain_cmake,
    ]


def _current_toolchain_impl(ctx):
    additional_sets = {}
    transitive_depsets = []

    if ctx.attr.is_macos:
        macos_sdk_toolchain = ctx.toolchains["//vcpkg/bootstrap/macos:sdk_toolchain_type"]
        if macos_sdk_toolchain:
            additional_sets["VCPKG_OSX_SYSROOT"] = "\"$ENV{VCPKG_EXEC_ROOT}/%s\"" % macos_sdk_toolchain.macos_sdk_info.path

            # TODO: make this configurable
            additional_sets["VCPKG_OSX_DEPLOYMENT_TARGET"] = macos_sdk_toolchain.macos_sdk_info.deployment_target
            transitive_depsets.append(macos_sdk_toolchain.macos_sdk_info.files)

    vcpkg_toolchain = ctx.toolchains["@rules_vcpkg//vcpkg/toolchain:toolchain_type"]
    if vcpkg_toolchain:
        additional_sets |= vcpkg_toolchain.vcpkg_info.config_settings

    transitive_depsets.append(ctx.toolchains["@rules_cc//cc:toolchain_type"].cc.all_files)

    release_overlay_tripplets = _create_overlay_tripplets(ctx, "release", additional_sets)
    debug_overlay_tripplets = _create_overlay_tripplets(ctx, "debug", additional_sets)

    tools_info = get_tools_info(ctx)

    return [
        DefaultInfo(files = depset(release_overlay_tripplets + debug_overlay_tripplets)),
        platform_common.ToolchainInfo(
            vcpkg_current_info = VcpgCurrentInfo(
                binaries = depset([]),
                transitive = depset(transitive = transitive_depsets),
                triplet = ctx.attr.triplet,
                overlay_triplets = depset(release_overlay_tripplets),
                overlay_tripplets_debug = depset(debug_overlay_tripplets),
                cc_compiler = _resolve_tool_path(tools_info.cc),
                cxx_compiler = _resolve_tool_path(tools_info.cxx),
            ),
        ),
    ]

current_toolchain = rule(
    implementation = _current_toolchain_impl,
    attrs = {
        "substitutions": attr.string_dict(
            doc = "Vcpkg platform substitutions",
            mandatory = True,
        ),
        "triplet": attr.string(
            doc = "Vcpkg platform triplet",
            mandatory = True,
        ),
        "triplet_template": attr.label(
            doc = "Vcpkg triplet template",
            allow_single_file = True,
            mandatory = True,
        ),
        "toolchain_template": attr.label(
            doc = "VCPKG_CHAINLOAD_TOOLCHAIN_FILE template",
            allow_single_file = True,
            mandatory = True,
        ),
        "is_macos": attr.bool(
            doc = "Is running on Mac OS X",
            default = False,
        ),
        "_vcpkg_cc_info": attr.label(
            default = "//vcpkg/toolchain/private:vcpkg_cc_info",
        ),
    },
    fragments = ["cpp"],
    toolchains = [
        "@rules_cc//cc:toolchain_type",
        config_common.toolchain_type(
            "@rules_vcpkg//vcpkg/toolchain:toolchain_type",
            mandatory = False,
        ),
        config_common.toolchain_type(
            "//vcpkg/bootstrap/macos:sdk_toolchain_type",
            mandatory = False,
        ),
    ],
)
