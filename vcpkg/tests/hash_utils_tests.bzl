load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//vcpkg/vcpkg_utils:hash_utils.bzl", "base64_encode_hexstr")

def _hash_utils_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, base64_encode_hexstr("5f"), "Xw==")
    asserts.equals(env, base64_encode_hexstr("5f87"), "X4c=")
    asserts.equals(env, base64_encode_hexstr("5f87ff"), "X4f/")
    asserts.equals(env, base64_encode_hexstr("5f87ff"), "X4f/")
    asserts.equals(env, base64_encode_hexstr("5f87ffdb"), "X4f/2w==")
    asserts.equals(env, base64_encode_hexstr("5f87ffdb83"), "X4f/24M=")
    asserts.equals(env, base64_encode_hexstr("5f87ffdb8383"), "X4f/24OD")
    return unittest.end(env)

hash_utils_test = unittest.make(_hash_utils_test_impl)

def hash_utils_test_suite():
    unittest.suite(
        "hash_utils_test",
        partial.make(hash_utils_test, timeout = "short"),
    )
