# load("@bazel_skylib//lib:paths.bzl", "paths")

DEFAULT_TRIPLET_SETS = {
    "X_VCPKG_BUILD_GNU_LIBICONV": "1",
}

DEFAULT_TRIPLET_DEFINITIONS = [
    "__DATE__=",
    "__TIMESTAMP__=",
    "__TIME__=",
]

DEFAULT_TRIPLET_CFLAGS = [
    "-Wno-builtin-macro-redefined",
]

def _to_cflags(definitions):
    return ["-D%s" % d for d in definitions]

DEFAULT_TIPLET_LISTS = {
    "VCPKG_C_FLAGS": _to_cflags(DEFAULT_TRIPLET_DEFINITIONS) + DEFAULT_TRIPLET_CFLAGS,
    "VCPKG_CXX_FLAGS": _to_cflags(DEFAULT_TRIPLET_DEFINITIONS) + DEFAULT_TRIPLET_CFLAGS,
}

def format_additions(lists, sets):
    """Format CMAKE-style definitions

    Args:
        lists: list type variable to append values to
        sets: variables to assign value to

    Returns:
        composed dictionary for template substitution
    """
    result = []
    if lists:
        for k, values in lists.items():
            result += [
                "string(APPEND %s \" %s\")" % (k, v)
                for v in values
            ] + [""]

    if sets:
        result += [
            "set(%s %s)" % item
            for item in sets.items()
        ] + [""]

    return {"%%ADDITIONS%%": "\n".join(result)}

VcpgCurrentInfo = provider(
    doc = "Information about current binaries from registered toolchains used with vcpkg.",
    fields = [
        "binaries",
        "transitive",
        "triplet",
        "overlay_triplets",
        # "cxx_compiler_str",
    ],
)

def _current_toolchain_impl(ctx):
    additional_sets = {}
    binaries = []
    transitive_depsets = []

    # TODO: Setup chainload file for resolved C++ toolchain
    # cc_compiler_str = None
    # cc_toolchain = ctx.toolchains["@rules_cc//cc:toolchain_type"]
    # for file in cc_toolchain.cc.all_files.to_list():
    #     if file.path.endswith(cc_toolchain.cc.compiler_executable):
    #         cc_link = ctx.actions.declare_file("bin/cc")
    #         ctx.actions.symlink(
    #             output = cc_link,
    #             target_file = file,
    #             is_executable = True,
    #         )
    #         cc_compiler_str = cc_link.path
    #         binaries.append(cc_link)

    # if not cc_compiler_str:
    #     fail("Can't detect CXX compiler path")

    # cxx_compiler_resolved = (
    #     cc_compiler_str if paths.is_absolute(cc_compiler_str) else "\"$ENV{VCPKG_EXEC_ROOT}/%s\"" % cc_compiler_str
    # )

    macos_sdk_toolchain = ctx.toolchains["//vcpkg/bootstrap/macos:sdk_toolchain_type"]
    if macos_sdk_toolchain:
        additional_sets["VCPKG_OSX_SYSROOT"] = "\"$ENV{VCPKG_EXEC_ROOT}/%s\"" % macos_sdk_toolchain.macos_sdk_info.path

        # TODO: make this configurable
        additional_sets["VCPKG_OSX_DEPLOYMENT_TARGET"] = macos_sdk_toolchain.macos_sdk_info.deployment_target
        transitive_depsets.append(macos_sdk_toolchain.macos_sdk_info.files)

    triplet_cmake = ctx.actions.declare_file("overlay_triplets/%s.cmake" % ctx.attr.triplet)
    toolchain_cmake = ctx.actions.declare_file("overlay_triplets/toolchain.cmake")

    additional_sets["VCPKG_CHAINLOAD_TOOLCHAIN_FILE"] = "\"$ENV{VCPKG_EXEC_ROOT}/%s\"" % toolchain_cmake.path

    # additional_sets["VCPKG_DETECTED_CMAKE_C_COMPILER"] = cxx_compiler_resolved
    # additional_sets["VCPKG_DETECTED_CMAKE_CXX_COMPILER"] = cxx_compiler_resolved
    # transitive_depsets.append(cc_toolchain.cc.all_files)

    ctx.actions.expand_template(
        template = ctx.file.triplet_template,
        output = triplet_cmake,
        substitutions = ctx.attr.substitutions | format_additions(
            DEFAULT_TIPLET_LISTS,
            DEFAULT_TRIPLET_SETS | additional_sets,
        ),
    )

    ctx.actions.expand_template(
        template = ctx.file.toolchain_template,
        output = toolchain_cmake,
        substitutions = ctx.attr.substitutions | {
            # TODO: Setup chainload file for resolved C++ toolchain
            # "%%CXX_COMPILER%%": cxx_compiler_resolved,
        },
    )

    return [
        DefaultInfo(files = depset(binaries + [
            triplet_cmake,
            toolchain_cmake,
        ])),
        platform_common.ToolchainInfo(
            vcpkg_current_info = VcpgCurrentInfo(
                binaries = depset(binaries),
                transitive = depset(transitive = transitive_depsets),
                triplet = ctx.attr.triplet,
                overlay_triplets = depset([
                    triplet_cmake,
                    toolchain_cmake,
                ]),
                # cxx_compiler_str = (
                #     cc_compiler_str if paths.is_absolute(cc_compiler_str) else "${VCPKG_EXEC_ROOT}/%s" % cc_compiler_str
                # ),
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
    },
    toolchains = [
        # "@rules_python//python:toolchain_type",
        # "@rules_cc//cc:toolchain_type",
        config_common.toolchain_type(
            "//vcpkg/bootstrap/macos:sdk_toolchain_type",
            mandatory = False,
        ),
    ],
)
