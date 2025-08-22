def _cc_toolchain_util_impl(rctx):
    rctx.download(
        output = "cc_toolchain_util.bzl",
        url = "https://raw.githubusercontent.com/bazel-contrib/rules_foreign_cc/refs/tags/0.15.1/foreign_cc/private/cc_toolchain_util.bzl",
        sha256 = "f2bf6157cbd6df5e0c825b3979ca6cd4f3a265a6859bf730795d960537ed1aa4",
    )
    rctx.file("BUILD.bazel", "")

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    else:
        return None

cc_toolchain_util = repository_rule(
    implementation = _cc_toolchain_util_impl,
)
