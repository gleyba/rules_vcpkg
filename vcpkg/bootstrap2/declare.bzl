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
        "lockfile": attr.label(
            mandatory = True,
            doc = "Lockfile with packages dependencies closure",
        ),
        "bootstrap_lockfile": attr.label(
            mandatory = True,
            doc = "Lockfile genmerated by 'vcpkg_bootstrap' repo, to compare with 'lockfile' for being actual",
        ),
    },
)
