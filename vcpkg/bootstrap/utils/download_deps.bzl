load("@bazel_skylib//lib:paths.bzl", "paths")
load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")
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

def _try_download_something(rctx, output, depend_info):
    errors_top = []
    for port in depend_info.keys():
        rctx.file(
            "%s/assets/%s/get_asset.sh" % (output, port),
            _GET_PORT_ASSETS_SH,
            executable = True,
        )
        rctx.file(
            "%s/assets/%s/BUILD.bazel" % (output, port),
            _PORT_ASSETS_BUILD_TPL.format(port = port),
            executable = False,
        )

        portfile = rctx.path("%s/vcpkg/ports/%s/portfile.cmake" % (output, port))
        if not portfile.exists:
            return None, "Can't find portfile.cmake for %s" % port

        vcpkg_json = rctx.path("%s/vcpkg/ports/%s/vcpkg.json" % (output, port))
        if not vcpkg_json.exists:
            errors_top.append("%s: can't find vcpkg.json for %s" % port)
            continue

        info = json.decode(rctx.read(vcpkg_json))
        if not info:
            errors_top.append("%s: can't decode vcpkg.json" % port)
            continue

        if not "version" in info:
            errors_top.append("%s: can't find 'version' in vcpkg.json" % port)
            continue

        def vcpkg_download_distfile(urls, sha512):
            asset_location = "collect_assets/%s" % sha512
            rctx.download(
                url = urls,
                output = asset_location,
                integrity = "sha512-%s" % base64_encode_hexstr(sha512),
            )

            _, err = exec_check(
                rctx,
                "Moving %s to assets" % asset_location,
                [
                    "ln",
                    asset_location,
                    "%s/assets/%s/%s" % (
                        output,
                        port,
                        sha512,
                    ),
                ],
                workdir = output,
            )

            if err:
                return [err]
            else:
                return []

        errors = cmake_parser(
            rctx.read(portfile),
            "%s portfile.cmake" % port,
            [
                struct(
                    name = "vcpkg_download_distfile",
                    args = ["URLS", "SHA512"],
                    call = vcpkg_download_distfile,
                ),
            ],
            substitutions = {
                "VERSION": info["version"],
            },
        )

        if errors:
            errors_top += errors

    return errors_top

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

def _run_install_loop(rctx, output, tmpdir, external_bins):
    def cleanup():
        rctx.delete("collect_assets.csv")
        rctx.delete("collect_assets.sh")

    def on_error(err):
        cleanup()
        return None, err

    full_path = str(rctx.path(output))

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
        rctx.file("collect_assets.csv", "", executable = False)

        # Call `install --only-downloads` jsut to collect csv with urls and sha512
        _, err = vcpkg_exec(rctx, "install", install_args, output, tmpdir, external_bins)
        if err:
            return on_error(err)

        if attempt:
            err = _extract_downloads(rctx, downloads, output, attempt)
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
        for url, sha512 in to_download:
            rctx.download(
                url = url,
                output = "collect_assets/%s" % sha512,
                integrity = "sha512-%s" % base64_encode_hexstr(sha512),
            )

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

def download_deps(rctx, output, tmpdir, depend_info, external_bins, verbose):
    def cleanup():
        rctx.delete("collect_assets")

    def on_error(err):
        cleanup()
        return None, err

    for dir in ["%s/downloads" % tmpdir, "collect_assets"]:
        _, err = exec_check(
            rctx,
            "Creating %s" % dir,
            ["mkdir", dir],
            workdir = output,
        )
        if err:
            return on_error(err)

    errors = _try_download_something(rctx, output, depend_info)
    if verbose:
        print(L.warn(*errors))

    downloads, err = _run_install_loop(rctx, output, tmpdir, external_bins)
    if err:
        return on_error(err)

    _, err = exec_check(
        rctx,
        "Moving downloads",
        [
            "mv",
            "%s/downloads" % tmpdir,
            "downloads",
        ],
        workdir = output,
    )

    if err:
        return on_error(err)

    cleanup()

    return downloads, None
