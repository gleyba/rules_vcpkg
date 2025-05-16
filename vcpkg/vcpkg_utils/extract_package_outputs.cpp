#include <string>
#include <optional>
#include <filesystem>
#include <algorithm>

namespace fs = std::filesystem;

inline bool ends_with(const std::string& value, const std::string& ending) {
    if (ending.size() > value.size()) return false;
    return std::equal(ending.rbegin(), ending.rend(), value.rbegin());
}

#include <iostream>

int main(int argc, char ** argv) {
    fs::path package_output_dir { argv[1] };
    fs::path output_dir { argv[2] };
    fs::path scan_dir = package_output_dir / argv[3];
    std::optional<std::string> extension;
    if (argc == 5) {
        extension = argv[4];
    }

    fs::create_directories(output_dir);

    for (auto const& dir_entry : fs::recursive_directory_iterator{scan_dir}) {
        if (dir_entry.is_directory()) {
            continue;
        }
     
        auto entry_path = dir_entry.path();

        if (extension && !ends_with(entry_path.filename(), extension.value())) {
            continue;
        }
        
        auto relative_path = entry_path.lexically_relative(scan_dir);

        auto install_path = output_dir / relative_path;

        fs::create_directories(install_path.parent_path());

        fs::copy_file(entry_path, install_path);
    }

    return 0;
}