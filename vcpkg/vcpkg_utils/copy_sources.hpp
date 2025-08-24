#pragma once

#include <filesystem>

void copy_sources(
    const std::filesystem::path& src,
    const std::filesystem::path& dst,
    std::filesystem::copy_options co,
    bool use_symlinks
);