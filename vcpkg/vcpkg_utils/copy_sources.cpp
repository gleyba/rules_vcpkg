#include <filesystem>

#include "copy_sources.hpp"

namespace fs = std::filesystem;

void copy_sources(
    const fs::path& src,
    const fs::path& dst,
    bool reuse_existing,
    bool use_symlinks
) {
    fs::create_directories(dst);

    for (const auto& buildtree_entry: fs::directory_iterator {src}) {
        auto buildtree_entry_path = buildtree_entry.path();
        auto relative_path = buildtree_entry_path.lexically_relative(src);
        auto dst_builtree_path = dst / relative_path;
        if (buildtree_entry.is_directory()) {
            copy_sources(
                buildtree_entry_path,
                dst_builtree_path,
                reuse_existing,
                use_symlinks
            );
        } else if (!use_symlinks) {
            fs::copy_file(
                buildtree_entry_path, 
                dst_builtree_path,
                reuse_existing
                    ? fs::copy_options::update_existing
                    : fs::copy_options::none
            );
        } else {
            if (fs::exists(dst_builtree_path)) {
                fs::remove(dst_builtree_path);
            }

            fs::create_symlink(
                fs::absolute(buildtree_entry_path),
                dst_builtree_path
            );
        }
    }
}