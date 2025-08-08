load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")

def cmake_parse_downloader(rctx, data, mnemo, download_clbk, substitutions):
    def _vcpkg_download_distfile(parse_ctx, urls, sha512):
        download_clbk(urls, sha512, parse_ctx.on_err)

    return cmake_parser(
        data = data,
        mnemo = mnemo,
        funcs_defs = {
            "vcpkg_download_distfile": [
                struct(
                    match_args = ["URLS", "SHA512"],
                    call = _vcpkg_download_distfile,
                ),
            ],
        },
        substitutions = substitutions,
    )
