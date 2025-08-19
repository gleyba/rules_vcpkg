load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "exec_check")
load("//vcpkg/vcpkg_utils:platform_utils.bzl", "platform_utils")

_BUILD_BAZEL = """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(
    name = "root",
    srcs = glob(
        [ "**" ],
        exclude = [ "bin/**" ],
    ),
    visibility = ["//visibility:public"],
)
"""

_BIN_BUILD_BAZEL = """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(
    name = "bin",
    srcs = glob([ "**" ]),
    visibility = ["//visibility:public"],
)
"""

def _symlink_rel(rctx, target, link_name):
    _, err = exec_check(rctx, "symlink", ["coreutils/coreutils", "ln", "-s", target, link_name])
    if err:
        fail(err)

def _process(rctx, def_name, defs, pu):
    if not def_name in defs:
        return

    cur_defs = defs[def_name]

    for kwargs in cur_defs.get("download_and_extract", []):
        rctx.download_and_extract(**kwargs)

    for kwargs in cur_defs.get("symlink", []):
        rctx.symlink(
            kwargs.pop("target"),
            kwargs.pop("link_name"),
        )

    for kwargs in cur_defs.get("extract", []):
        rctx.extract(
            archive = Label(kwargs.pop("archive").format(
                os = pu.definitions.os.name,
                arch = pu.definitions.arch.name,
            )),
            **kwargs
        )

    for kwargs in cur_defs.get("symlink_rel", []):
        _symlink_rel(rctx, **kwargs)

    if "symlink_coreutils" in cur_defs:
        if def_name != "_":
            fail("'symlink_coreutils' only allowed for wildcard platform")

        coretools_res, err = exec_check(rctx, "list coreutils", ["coreutils/coreutils", "--list"])
        if err:
            fail(err)

        for coretool in coretools_res.stdout.split("\n"):
            coretool = coretool.strip()
            if coretool in ["[", ""]:
                continue

            _symlink_rel(rctx, "../coreutils/coreutils", "bin/%s" % coretool)

def _bootstrap_toolchains_impl(rctx):
    defs = json.decode(rctx.read(rctx.path(rctx.attr.defs)))
    pu = platform_utils(rctx)

    _process(rctx, pu.definitions.os.name, defs, pu)
    _process(rctx, "%s_%s" % (pu.definitions.os.name, pu.definitions.arch.name), defs, pu)
    _process(rctx, "_", defs, pu)

    rctx.file(
        "BUILD.bazel",
        _BUILD_BAZEL,
    )

    rctx.file(
        "bin/BUILD.bazel",
        _BIN_BUILD_BAZEL,
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    else:
        return None

bootstrap_toolchains = repository_rule(
    implementation = _bootstrap_toolchains_impl,
    attrs = {
        "defs": attr.label(default = Label("//vcpkg/bootstrap/external:toolchains_defs.json")),
    },
)
