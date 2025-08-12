load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//vcpkg/bootstrap/utils:cmake_parser.bzl", "cmake_parser")

def _lbpng_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(_parse_ctx, urls, sha512):
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
        {
            "vcpkg_download_distfile": [
                struct(
                    match_args = ["URLS", "SHA512"],
                    call = check_vcpkg_download_distfile,
                ),
            ],
        },
        {"VERSION": "123"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

lbpng_test = unittest.make(_lbpng_test_impl)

def _icu_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(_parse_ctx, urls, sha512):
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
        {
            "vcpkg_download_distfile": [
                struct(
                    match_args = ["URLS", "SHA512"],
                    call = check_vcpkg_download_distfile,
                ),
            ],
        },
        {"VERSION": "1.2.3"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

icu_test = unittest.make(_icu_test_impl)

def _libiconv_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(_parse_ctx, urls, sha512):
        asserts.equals(
            env,
            [
                "https://ftp.gnu.org/gnu/libiconv/libiconv-1.2.3.tar.gz",
                "https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/libiconv/libiconv-1.2.3.tar.gz",
            ],
            urls,
        )
        asserts.equals(env, "a55eb3b7b785a78ab8918db8af541c9e11deb5ff4f89d54483287711ed797d87848ce0eafffa7ce26d9a7adb4b5a9891cb484f94bd4f51d3ce97a6a47b4c719a", sha512)

    errors = cmake_parser(
        """\
    vcpkg_download_distfile(ARCHIVE
        URLS "https://ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz"
            "https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz"
        FILENAME "libiconv-${VERSION}.tar.gz"
        SHA512 a55eb3b7b785a78ab8918db8af541c9e11deb5ff4f89d54483287711ed797d87848ce0eafffa7ce26d9a7adb4b5a9891cb484f94bd4f51d3ce97a6a47b4c719a
    )
""",
        "libiconv_test",
        {
            "vcpkg_download_distfile": [
                struct(
                    match_args = ["URLS", "SHA512"],
                    call = check_vcpkg_download_distfile,
                ),
            ],
        },
        {"VERSION": "1.2.3"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

libiconv_test = unittest.make(_libiconv_test_impl)

def _double_conversion_test_impl(ctx):
    env = unittest.begin(ctx)

    def check_vcpkg_download_distfile(_parse_ctx, urls, sha512):
        asserts.equals(env, "https://github.com/google/double-conversion/commit/101e1ba89dc41ceb75090831da97c43a76cd2906.patch?full_index=1", urls)
        asserts.equals(env, "a946a1909b10f3ac5262cbe5cd358a74cf018325223403749aaeb81570ef3e2f833ee806afdefcd388e56374629de8ccca0a1cef787afa481c79f9e8f8dcaa13", sha512)

    errors = cmake_parser(
        """\
        vcpkg_download_distfile(PATCH_501_FIX_CMAKE_3_5
        URLS https://github.com/google/double-conversion/commit/101e1ba89dc41ceb75090831da97c43a76cd2906.patch?full_index=1
        SHA512 a946a1909b10f3ac5262cbe5cd358a74cf018325223403749aaeb81570ef3e2f833ee806afdefcd388e56374629de8ccca0a1cef787afa481c79f9e8f8dcaa13
        FILENAME google-double-conversion-101e1ba89dc41ceb75090831da97c43a76cd2906.patch
    )
""",
        "double_conversion_test",
        {
            "vcpkg_download_distfile": [
                struct(
                    match_args = ["URLS", "SHA512"],
                    call = check_vcpkg_download_distfile,
                ),
            ],
        },
        {"VERSION": "1.2.3"},
    )

    asserts.equals(env, [], errors)

    return unittest.end(env)

double_conversion_test = unittest.make(_double_conversion_test_impl)

def cmake_parser_test_suite():
    unittest.suite(
        "cmake_parser_test",
        partial.make(lbpng_test, timeout = "short"),
        partial.make(icu_test, timeout = "short"),
        partial.make(libiconv_test, timeout = "short"),
        partial.make(double_conversion_test, timeout = "short"),
    )
