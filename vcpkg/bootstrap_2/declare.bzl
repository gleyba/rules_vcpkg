def _declare_impl(rctx):
    print(rctx.path(rctx.attr.bootstrap_lockfile))
    rctx.file("BUILD.bazel", "")

declare = repository_rule(
    implementation = _declare_impl,
    attrs = {
        "bootstrap_repo": attr.string(
            mandatory = True,
            doc = "Repository name with vcpkg bootstrap",
        ),
        "bootstrap_lockfile": attr.label(
            mandatory = True,
            doc = "Lockfile with packages dependencies closure",
        ),
    },
)