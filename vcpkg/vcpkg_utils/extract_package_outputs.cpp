#include <string>
#include <optional>
#include <fstream>
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
    std::string collect_type { argv[4] };
    fs::path empty_lib { argv[5] };
    std::vector<std::string> extensions;
    if (collect_type == "libs") {
        extensions = { ".a", ".o" };
    }

    fs::create_directories(output_dir);

    std::size_t files_copied = 0;
    if (fs::exists(scan_dir)) {
        for (const auto& dir_entry : fs::recursive_directory_iterator{scan_dir}) {
            if (dir_entry.is_directory()) {
                continue;
            }
        
            auto entry_path = dir_entry.path();

            if (!extensions.empty()) {
                bool need_skip = true;
                for (const std::string& extension: extensions) {
                    if (ends_with(entry_path.filename(), extension)) {
                        need_skip = false;
                        break;
                    }
                }
                if (need_skip) {
                    continue;
                }
            }
            
            auto relative_path = entry_path.lexically_relative(scan_dir);

            auto install_path = output_dir / relative_path;

            fs::create_directories(install_path.parent_path());

            fs::copy_file(entry_path, install_path);
            files_copied += 1;
        }
    }

    if (files_copied == 0 && collect_type == "libs") {
        fs::copy_file(empty_lib, output_dir / "lib_.a");
    }

    return 0;
}