load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")

_DATA = """\
    set(LIBPNG_APNG_PATCH_NAME "libpng-${VERSION}-apng.patch")
    vcpkg_download_distfile(LIBPNG_APNG_PATCH_ARCHIVE
        URLS "https://downloads.sourceforge.net/project/libpng-apng/libpng16/${VERSION}/${LIBPNG_APNG_PATCH_NAME}.gz"
        FILENAME "${LIBPNG_APNG_PATCH_NAME}.gz"
        SHA512 f9b3b5ef42a7d3e61b435af69e04174c9ea6319d8fc8b5fd3443a3a9f0a0e9803bc2b0fe6658a91d0a76b06dfd846d29b63edffebeedd1cb26f4d2cf0c87f8b1
    )
"""

def _cmake_parser_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(urls, sha512):
        asserts.equals(env, "https://downloads.sourceforge.net/project/libpng-apng/libpng16/123/libpng-123-apng.patch.gz", urls)
        asserts.equals(env, "f9b3b5ef42a7d3e61b435af69e04174c9ea6319d8fc8b5fd3443a3a9f0a0e9803bc2b0fe6658a91d0a76b06dfd846d29b63edffebeedd1cb26f4d2cf0c87f8b1", sha512)

    errors = cmake_parser(
        _DATA,
        "cmake_parser_test",
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

cmake_parser_test = unittest.make(_cmake_parser_test_impl)

def cmake_parser_test_suite():
    unittest.suite(
        "cmake_parser_test",
        partial.make(cmake_parser_test, timeout = "short"),
    )
