#pragma once

#include <filesystem>

void copy_sources(
    const std::filesystem::path& src,
    const std::filesystem::path& dst,
    bool reuse_existing,
    bool use_symlinks
);