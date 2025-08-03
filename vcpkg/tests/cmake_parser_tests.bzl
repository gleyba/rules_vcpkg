load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")

def _lbpng_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(urls, sha512):
        asserts.equals(env, "https://downloads.sourceforge.net/project/libpng-apng/libpng16/123/libpng-123-apng.patch.gz", urls)
        asserts.equals(env, "f9b3b5ef42a7d3e61b435af69e04174c9ea6319d8fc8b5fd3443a3a9f0a0e9803bc2b0fe6658a91d0a76b06dfd846d29b63edffebeedd1cb26f4d2cf0c87f8b1", sha512)

    errors = cmake_parser(
        """\
        set(LIBPNG_APNG_PATCH_NAME "libpng-${VERSION}-apng.patch")
        vcpkg_download_distfile(LIBPNG_APNG_PATCH_ARCHIVE
            URLS "https://downloads.sourceforge.net/project/libpng-apng/libpng16/${VERSION}/${LIBPNG_APNG_PATCH_NAME}.gz"
            FILENAME "${LIBPNG_APNG_PATCH_NAME}.gz"
            SHA512 f9b3b5ef42a7d3e61b435af69e04174c9ea6319d8fc8b5fd3443a3a9f0a0e9803bc2b0fe6658a91d0a76b06dfd846d29b63edffebeedd1cb26f4d2cf0c87f8b1
        )
""",
        "lbpng_test",
        [
            struct(
                name = "vcpkg_download_distfile",
                args = ["URLS", "SHA512"],
                call = check_vcpkg_download_distfile,
            ),
        ],
        {"VERSION": "123"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

lbpng_test = unittest.make(_lbpng_test_impl)

def _icu_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(urls, sha512):
        asserts.equals(env, "https://github.com/unicode-org/icu/releases/download/release-1-2-3/icu4c-1_2_3-src.tgz", urls)
        asserts.equals(env, "e6c7876c0f3d756f3a6969cad9a8909e535eeaac352f3a721338b9cbd56864bf7414469d29ec843462997815d2ca9d0dab06d38c37cdd4d8feb28ad04d8781b0", sha512)

    errors = cmake_parser(
        """\
        string(REPLACE "." "_" VERSION2 "${VERSION}")
        string(REPLACE "." "-" VERSION3 "${VERSION}")

        vcpkg_download_distfile(
            ARCHIVE
            URLS "https://github.com/unicode-org/icu/releases/download/release-${VERSION3}/icu4c-${VERSION2}-src.tgz"
            FILENAME "icu4c-${VERSION2}-src.tgz"
            SHA512 e6c7876c0f3d756f3a6969cad9a8909e535eeaac352f3a721338b9cbd56864bf7414469d29ec843462997815d2ca9d0dab06d38c37cdd4d8feb28ad04d8781b0
        )
""",
        "icu_test",
        [
            struct(
                name = "vcpkg_download_distfile",
                args = ["URLS", "SHA512"],
                call = check_vcpkg_download_distfile,
            ),
        ],
        {"VERSION": "1.2.3"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

icu_test = unittest.make(_icu_test_impl)

def cmake_parser_test_suite():
    unittest.suite(
        "cmake_parser_test",
        partial.make(lbpng_test, timeout = "short"),
        partial.make(icu_test, timeout = "short"),
    )
