load("@bazel_skylib//lib:paths.bzl", "paths")

VcpgCurrentInfo = provider(
    doc = "Information about current binaries from registered toolchains used with vcpkg.",
    fields = [
        "binaries",
        "transitive",
        "triplet",
        "overlay_triplets",
        "cxx_compiler_str",
    ],
)

def _current_toolchain_impl(ctx):
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"]
    if not py_toolchain.py3_runtime:
        fail("No PY3 runtime defined")

    python3 = ctx.actions.declare_file("bin/python3")
    ctx.actions.symlink(
        output = python3,
        target_file = py_toolchain.py3_runtime.interpreter,
        is_executable = True,
    )

    binaries = [python3]

    cc_compiler_str = None
    cc_toolchain = ctx.toolchains["@rules_cc//cc:toolchain_type"]
    for file in cc_toolchain.cc.all_files.to_list():
        if file.path.endswith(cc_toolchain.cc.compiler_executable):
            cc_link = ctx.actions.declare_file("bin/cc")
            ctx.actions.symlink(
                output = cc_link,
                target_file = file,
                is_executable = True,
            )
            cc_compiler_str = cc_link.path
            binaries.append(cc_link)
            break

    if not cc_compiler_str:
        fail("Can't detect CXX compiler path")

    substitutions = {
        "%%ARCH_SHORT%%": ctx.attr.arch_short,
        "%%ARCH_LONG%%": ctx.attr.arch_long,
        "%%SYSTEM_NAME%%": ctx.attr.system_name,
        "%%CXX_COMPILER%%": (
            cc_compiler_str if paths.is_absolute(cc_compiler_str) else "$ENV{VCPKG_EXEC_ROOT}/%s" % cc_compiler_str
        ),
    }

    triplet_cmake = ctx.actions.declare_file("overlay_triplets/%s.cmake" % ctx.attr.triplet)
    ctx.actions.expand_template(
        template = ctx.file.triplet_template,
        output = triplet_cmake,
        substitutions = substitutions,
    )
    toolchain_cmake = ctx.actions.declare_file("overlay_triplets/toolchain.cmake")
    ctx.actions.expand_template(
        template = ctx.file.toolchain_template,
        output = toolchain_cmake,
        substitutions = substitutions,
    )

    return [
        DefaultInfo(files = depset(binaries + [
            triplet_cmake,
            toolchain_cmake,
        ])),
        platform_common.ToolchainInfo(
            vcpkg_current_info = VcpgCurrentInfo(
                binaries = depset(binaries),
                transitive = depset(transitive = [
                    py_toolchain.py3_runtime.files,
                    cc_toolchain.cc.all_files,
                ]),
                triplet = ctx.attr.triplet,
                overlay_triplets = depset([
                    triplet_cmake,
                    toolchain_cmake,
                ]),
                cxx_compiler_str = (
                    cc_compiler_str if paths.is_absolute(cc_compiler_str) else "${VCPKG_EXEC_ROOT}/%s" % cc_compiler_str
                ),
            ),
        ),
    ]

current_toolchain = rule(
    implementation = _current_toolchain_impl,
    attrs = {
        "arch_short": attr.string(
            doc = "Architecture, short version",
            mandatory = True,
        ),
        "arch_long": attr.string(
            doc = "Architecture, long version",
            mandatory = True,
        ),
        "system_name": attr.string(
            doc = "Operation system name",
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
        "@rules_python//python:toolchain_type",
        "@rules_cc//cc:toolchain_type",
    ],
)
