DEFAULT_CONFIG_SETTINGS = {
    "X_VCPKG_BUILD_GNU_LIBICONV": "1",
}

DEAULT_VCPKG_DISTRO_FIXUP_REPLACE = {
    "scripts/cmake/vcpkg_configure_make.cmake": [
        """set(ENV{CC} "$ENV{CC} $ENV{CPPFLAGS} $ENV{CFLAGS}")""",
        "",
        """set(ENV{CC_FOR_BUILD} "$ENV{CC_FOR_BUILD} $ENV{CPPFLAGS} $ENV{CFLAGS}")""",
        "",
    ],
}
