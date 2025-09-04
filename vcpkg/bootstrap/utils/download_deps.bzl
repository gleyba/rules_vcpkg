load("@bazel_skylib//lib:paths.bzl", "paths")
load("//vcpkg/bootstrap/utils:cmake_parse_downloader.bzl", "cmake_parse_downloader")
load("//vcpkg/bootstrap/utils:vcpkg_exec.bzl", "exec_check", "vcpkg_exec")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")
load("//vcpkg/vcpkg_utils:logging.bzl", "L")

_GET_PORT_ASSETS_SH = """\
#!/bin/bash

set -eux

cd "$(dirname "$0")"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dst) dst="$2"; shift ;;
        --sha512) sha512="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -f "${sha512}" ]; then
    ln "${sha512}" "${dst}"
fi
"""

_PORT_ASSETS_BUILD_TPL = """\
load("@bazel_skylib//rules/directory:directory.bzl", "directory")

directory(
    name = "{port}",
    srcs = glob(
        ["*"],
        allow_empty=True,
    ),
    visibility = ["//visibility:public"],
)
"""

_LIST_TYPE = type([])

# This thing allows better parallelization in downloads, also pull some distfiles, not covered
# by `_run_install_loop`, which unblocks setups with `--nosandbox_default_allow_network`.
# So, it worth its own wannabe cmake parser to exist.
def _try_download_something(rctx, bootstrap_ctx, depend_info):
    errors = []
    deferred_downloads = []

    for port in depend_info.keys():
        rctx.file(
            "%s/assets/%s/get_asset.sh" % (bootstrap_ctx.output, port),
            _GET_PORT_ASSETS_SH,
            executable = True,
        )
        rctx.file(
            "%s/assets/%s/BUILD.bazel" % (bootstrap_ctx.output, port),
            _PORT_ASSETS_BUILD_TPL.format(port = port),
            executable = False,
        )

        portfile = rctx.path("%s/vcpkg/ports/%s/portfile.cmake" % (bootstrap_ctx.output, port))
        if not portfile.exists:
            return None, "Can't find portfile.cmake for %s" % port

        vcpkg_json = rctx.path("%s/vcpkg/ports/%s/vcpkg.json" % (bootstrap_ctx.output, port))
        if not vcpkg_json.exists:
            errors.append("%s: can't find vcpkg.json for %s" % port)
            continue

        info = json.decode(rctx.read(vcpkg_json))
        if not info:
            errors.append("%s: can't decode vcpkg.json" % port)
            continue

        substitutions = {}
        if "version" in info:
            substitutions["VERSION"] = info["version"]
        elif "version-semver" in info:
            substitutions["VERSION"] = info["version-semver"]
        else:
            errors.append("%s: can't find 'version' in vcpkg.json" % port)

        def _download_clbk(url, sha512, _on_err):
            if type(url) == _LIST_TYPE:
                # Faster mirrors usually iun the end
                url = reversed(url)

            rctx.report_progress("Starting download: %s" % url)
            asset_location = "collect_assets/%s" % sha512

            deferred = rctx.download(
                url = url,
                output = asset_location,
                integrity = "sha512-%s" % base64_encode_hexstr(sha512),
                block = False,
                allow_fail = True,
            )
            deferred_downloads.append(struct(
                asset_location = asset_location,
                copy_to = "%s/assets/%s/%s" % (
                    bootstrap_ctx.output,
                    port,
                    sha512,
                ),
                deferred = deferred,
            ))

        errors += cmake_parse_downloader(
            rctx,
            bootstrap_ctx,
            rctx.read(portfile),
            "%s portfile.cmake" % port,
            download_clbk = _download_clbk,
            substitutions = substitutions,
        )

    rctx.report_progress("Merging deferred downloads")
    for dd in deferred_downloads:
        dd.deferred.wait()
        _, err = exec_check(
            rctx,
            "Moving %s to assets" % dd.asset_location,
            [
                "ln",
                dd.asset_location,
                dd.copy_to,
            ],
            workdir = bootstrap_ctx.output,
        )
        if err:
            errors.append(err)

    return errors

_DOWNLOAD_TRY_PREFIX = "Trying to download "
_DOWNLOAD_TRY_POSTFIX = " using asset cache script"
_USING_CACHED_PREFIX = "-- Using cached "
_DOWNLOAD_LOOP_ATTEMPTS = 8

def _extract_downloads(rctx, result, output, attempt):
    if attempt == _DOWNLOAD_LOOP_ATTEMPTS:
        return "\n".join([
            "We ran 'vcpkg install --only-downloads' to collect downloads %s times," % _DOWNLOAD_LOOP_ATTEMPTS,
            "but didn't collect all, probably we are in corrupted state",
        ])

    rctx.report_progress("`vcpkg install --only-downloads` loop #%s, parsing buildtrees logfiles for downloads" % attempt)
    for buildtree in rctx.path("%s/vcpkg/buildtrees" % output).readdir():
        downloads = set()
        for buildtree_inner in buildtree.readdir():
            if buildtree_inner.basename.endswith(".log"):
                if buildtree_inner.basename.startswith("stdout"):
                    buildtree_log_content = rctx.read(buildtree_inner)
                    for line in buildtree_log_content.split("\n"):
                        if line.startswith(_DOWNLOAD_TRY_PREFIX):
                            if not line.endswith(_DOWNLOAD_TRY_POSTFIX):
                                return "Can't parse try-download line: %s" % line

                            download = line[len(_DOWNLOAD_TRY_PREFIX):-len(_DOWNLOAD_TRY_POSTFIX)].strip()
                        elif line.startswith(_USING_CACHED_PREFIX):
                            download = line[len(_USING_CACHED_PREFIX):].strip()
                        else:
                            continue

                        if download[0] == "/":
                            download = paths.basename(download)
                        downloads.add(download)

                rctx.delete(buildtree_inner)

        if buildtree.basename in result:
            result[buildtree.basename] |= downloads
        else:
            result[buildtree.basename] = downloads

    return None

def _run_install_loop(rctx, bootstrap_ctx):
    def cleanup():
        rctx.delete("collect_assets.csv")
        rctx.delete("collect_assets.sh")

    def on_error(err):
        cleanup()
        return None, err

    full_path = str(rctx.path(bootstrap_ctx.output))

    rctx.file("collect_assets.sh", _COLLECT_ASSETS_SH, executable = True)

    install_args = [
        "--only-downloads",
        "--x-asset-sources=%s" % ";".join([
            " ".join([
                "x-script,%s/collect_assets.sh" % full_path,
                "--url {url}",
                "--dst {dst}",
                "--sha512 {sha512}",
            ]),
            "x-block-origin",
        ]),
    ]

    downloads = {}

    # Just some number of iterations as a hack, should finish early
    for attempt in range(_DOWNLOAD_LOOP_ATTEMPTS + 1):
        rctx.report_progress("Run `vcpkg install --only-downloads` loop #%s" % attempt)
        rctx.file("collect_assets.csv", "", executable = False)

        # Call `install --only-downloads` jsut to collect csv with urls and sha512
        _, err = vcpkg_exec(rctx, "install", install_args, bootstrap_ctx)
        if err:
            return on_error(err)

        if attempt:
            err = _extract_downloads(rctx, downloads, bootstrap_ctx.output, attempt)
            if err:
                return on_error(err)

        to_download = [
            line.split(" ")
            for line in rctx.read("collect_assets.csv").split("\n")
            if line
        ]
        if not to_download:
            # After last `install --only-downloads` we must have downloads in place
            break

        # Actually download assets
        pending = {
            url: rctx.download(
                url = url,
                output = "collect_assets/%s" % sha512,
                integrity = "sha512-%s" % base64_encode_hexstr(sha512),
                block = False,
            )
            for url, sha512 in to_download
        }
        for url, p in pending.items():
            rctx.report_progress("`vcpkg install --only-downloads` loop #%s, waiting for download: %s" % (attempt, url))
            p.wait()

    return downloads, None

_COLLECT_ASSETS_SH = """\
#!/bin/bash

set -eu

cd "$(dirname "$0")"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --url) url="$2"; shift ;;
        --dst) dst="$2"; shift ;;
        --sha512) sha512="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -f "collect_assets/${sha512}" ]; then
    ln "collect_assets/${sha512}" "${dst}"
else
    echo "${url} ${sha512}" >> collect_assets.csv
fi
"""

def download_deps(rctx, bootstrap_ctx, depend_info):
    rctx.report_progress("Downloading VCPKG deps")

    def cleanup():
        rctx.delete("collect_assets")

    def on_error(err):
        cleanup()
        return None, err

    for dir in ["%s/downloads" % bootstrap_ctx.tmpdir, "collect_assets"]:
        _, err = exec_check(
            rctx,
            "Creating %s" % dir,
            ["mkdir", dir],
            workdir = bootstrap_ctx.output,
        )
        if err:
            return on_error(err)

    errors = _try_download_something(rctx, bootstrap_ctx, depend_info)
    if bootstrap_ctx.verbose:
        L.warn(*errors)

    downloads, err = _run_install_loop(rctx, bootstrap_ctx)
    if err:
        return on_error(err)

    _, err = exec_check(
        rctx,
        "Moving downloads",
        [
            "mv",
            "%s/downloads" % bootstrap_ctx.tmpdir,
            "downloads",
        ],
        workdir = bootstrap_ctx.output,
    )

    if err:
        return on_error(err)

    cleanup()

    return downloads, None
