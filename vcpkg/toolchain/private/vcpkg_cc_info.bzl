load("@bazel_skylib//lib:paths.bzl", "paths")
load("@cc_toolchain_util.bzl", "CxxFlagsInfo", "get_env_vars", "get_flags_info", "get_tools_info")

_collect_opt_flags_transition = transition(
    implementation = lambda _, __: {
        "//command_line_option:compilation_mode": "opt",
    },
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ],
)

_collect_dbg_flags_transition = transition(
    implementation = lambda _, __: {
        "//command_line_option:compilation_mode": "dbg",
    },
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ],
)

cc_flags = rule(
    implementation = get_flags_info,
    fragments = ["cpp"],
    toolchains = ["@rules_cc//cc:toolchain_type"],
)

def _resolve_tool_path(tool_path):
    if paths.is_absolute(tool_path):
        return tool_path
    else:
        return "$ENV{VCPKG_EXEC_ROOT}/%s" % tool_path

def _to_flags_list(flags):
    return " ".join([
        flag.replace('"', '\\\\\\"')
            .replace("-Lexternal", "-L$ENV{VCPKG_EXEC_ROOT}/external")
            .replace("-Iexternal", "-I$ENV{VCPKG_EXEC_ROOT}/external")
        for flag in flags
    ])

def _determine_ar(is_macos, cc):
    if not is_macos or not cc.ar_executable.endswith("libtool"):
        return _resolve_tool_path(cc.ar_executable)

    for file in cc.all_files.to_list():
        if file.basename == "ar" or file.basename == "llvm-ar":
            return _resolve_tool_path(file.path)

    return "ar"

VcpkgCCInfo = provider(
    doc = "Flags for the C/C++ tools, taken from the toolchain, both debug and release variant",
    fields = dict(
        env = "Environment variables",
        cc = "C compiler",
        cxx = "C++ compiler",
        ar = "AR executable",
        opt_cc_flags = "C compiler flags in release",
        opt_cxx_flags = "C++ compiler flags in release",
        opt_cxx_linker_shared = "C++ linker flags when linking shared library in release",
        opt_cxx_linker_static = "C++ linker flags when linking static library in release",
        opt_cxx_linker_executable = "C++ linker flags when linking executable in release",
        dbg_cc_flags = "C compiler flags in debug",
        dbg_cxx_flags = "C++ compiler flags in debug",
        dbg_cxx_linker_shared = "C++ linker flags when linking shared library in debug",
        dbg_cxx_linker_static = "C++ linker flags when linking static library in debug",
        dbg_cxx_linker_executable = "C++ linker flags when linking executable in debug",
    ),
)

def _vcpkg_cc_info_impl(ctx):
    tools_info = get_tools_info(ctx)
    env_vars = get_env_vars(ctx)

    opt_flags = ctx.attr._cc_opt_flags[0][CxxFlagsInfo]
    dbg_flags = ctx.attr._cc_dbg_flags[0][CxxFlagsInfo]

    cc_toolchain = ctx.toolchains["@rules_cc//cc:toolchain_type"]

    # for attr in dir(cc_toolchain.cc):
    #     print("%s:\n%s" % (attr, getattr(cc_toolchain.cc, attr)))

    result = VcpkgCCInfo(
        env = env_vars,
        cc = _resolve_tool_path(tools_info.cc),
        cxx = _resolve_tool_path(tools_info.cxx),
        ar = _determine_ar(ctx.attr.is_macos, cc_toolchain.cc),
        opt_cc_flags = _to_flags_list(opt_flags.cc),
        opt_cxx_flags = _to_flags_list(opt_flags.cxx),
        opt_cxx_linker_shared = _to_flags_list(opt_flags.cxx_linker_shared),
        opt_cxx_linker_static = _to_flags_list(opt_flags.cxx_linker_static),
        opt_cxx_linker_executable = _to_flags_list(opt_flags.cxx_linker_executable),
        dbg_cc_flags = _to_flags_list(dbg_flags.cc),
        dbg_cxx_flags = _to_flags_list(dbg_flags.cxx),
        dbg_cxx_linker_shared = _to_flags_list(dbg_flags.cxx_linker_shared),
        dbg_cxx_linker_static = _to_flags_list(dbg_flags.cxx_linker_static),
        dbg_cxx_linker_executable = _to_flags_list(dbg_flags.cxx_linker_executable),
    )

    # for attr in dir(result):
    #     print("%s:\n%s" % (attr, getattr(result, attr)))

    return result

vcpkg_cc_info = rule(
    implementation = _vcpkg_cc_info_impl,
    attrs = {
        "is_macos": attr.bool(
            doc = "Is running on Mac OS X",
            default = False,
        ),
        "_cc_opt_flags": attr.label(
            default = ":cc_flags",
            providers = [CxxFlagsInfo],
            cfg = _collect_opt_flags_transition,
        ),
        "_cc_dbg_flags": attr.label(
            default = ":cc_flags",
            providers = [CxxFlagsInfo],
            cfg = _collect_dbg_flags_transition,
        ),
    },
    fragments = ["cpp"],
    toolchains = ["@rules_cc//cc:toolchain_type"],
)
