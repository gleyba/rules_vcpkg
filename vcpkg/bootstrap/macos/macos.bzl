load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_sdk = tag_class(
    attrs = {
        "version": attr.string(doc = "Version of Mac OS X sdk to download, see `https://github.com/joseluisq/macosx-sdks`"),
    },
)

def _macos_impl(mctx):
    cur_sdk = None
    for mod in mctx.modules:
        for sdk in mod.tags.sdk:
            if cur_sdk:
                if cur_sdk.version < sdk.version:
                    tmp = cur_sdk
                    cur_sdk = sdk
                    sdk = tmp

                mctx.report_progress("Skip Mac OS X sdk version: %s, using a newer one" % sdk.version)
            else:
                cur_sdk = sdk

    if cur_sdk:
        mctx.download(
            "https://raw.githubusercontent.com/joseluisq/macosx-sdks/refs/tags/15.5/macosx_sdks.json",
            output = "macosx_sdks.json",
            sha256 = "1c2d06f54340529c5814a89cbf3061d2c040c568db0f1305dade64337edc98ba",
        )

        sdk_defs = {
            x["version"]: x
            for x in json.decode(mctx.read("macosx_sdks.json"))
        }

        sdk_def = sdk_defs["macOS %s" % cur_sdk.version]

        if not sdk_def:
            fail("Unable to find Mac OS X sdk with version %s at `https://github.com/joseluisq/macosx-sdks`" % cur_sdk.version)

        http_archive(
            name = "macos_sdk",
            url = sdk_def["github_download_url"],
            sha256 = sdk_def["github_download_sha256sum"],
            strip_prefix = "MacOSX%s.sdk" % cur_sdk.version,
            build_file = Label("//vcpkg/bootstrap/macos:BUILD.macos.sdk.tpl"),
        )

macos = module_extension(
    implementation = _macos_impl,
    tag_classes = {
        "sdk": _sdk,
    },
)
