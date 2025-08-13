load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")
load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "exec_check")

def cmake_parse_downloader(rctx, bootstrap_ctx, data, mnemo, download_clbk, substitutions):
    rctx.report_progress("Parsing %s" % mnemo)

    def _vcpkg_download_distfile(parse_ctx, urls, sha512):
        download_clbk(urls, sha512, parse_ctx.on_err)

    def _regex_replace(parse_ctx, *tokens):
        tokens_len = len(tokens)
        if tokens_len != 6:
            parse_ctx.on_err("len(tokens) == %s, but expected 6 for string(REGEX REPLACE ..." % tokens_len)
            return

        if tokens[0] != "REGEX" and tokens[1] != "REPLACE":
            parse_ctx.on_err(["Can only process string(REGEX REPLACE ..."])
            return

        value = parse_ctx.substitute(tokens[5])
        if value == None:
            return

        python_str = """import re; print(re.sub("%s", "%s", "%s"))""" % (
            tokens[2],
            tokens[3],
            value,
        )

        args = [
            "%s/python3" % bootstrap_ctx.external_bins,
            "-c",
            python_str,
        ]

        res, err = exec_check(rctx, "REGEX REPLACE", args)

        parse_ctx.on_err(err)

        if res == None:
            return

        parse_ctx.set(tokens[4], res.stdout.strip())

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
            "string": [
                struct(
                    match_tokens = ["REGEX", "REPLACE"],
                    call = _regex_replace,
                ),
            ],
        },
        substitutions = substitutions,
    )
