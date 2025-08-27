#include <string>
#include <filesystem>
#include <iostream>

namespace fs = std::filesystem;

int main(int argc, char ** argv) {
    std::string package_output_origin_dir_str { argv[1] };
    fs::path package_output_origin_dir { package_output_origin_dir_str };
    fs::path port_dir_str { argv[2] };

    for (const auto& dir_entry : fs::recursive_directory_iterator{package_output_origin_dir}) {
        fs::path entry_path = dir_entry.path();
        if (!fs::is_symlink(entry_path)) {
            continue;
        }

        fs::path link_destination = fs::read_symlink(entry_path);
        if (link_destination.is_relative()) {
            fs::remove(entry_path);
            fs::create_hard_link(
                entry_path.parent_path() / link_destination,
                dir_entry
            );
            continue;
        }

        std::string link_destination_str = link_destination.string();
        if (link_destination_str.find(package_output_origin_dir_str) == 0) {
            fs::remove(entry_path);
            fs::create_symlink(
                entry_path.lexically_relative(package_output_origin_dir.lexically_relative(link_destination)),
                entry_path
            );
            continue;
        }

        if (link_destination_str.find(port_dir_str) != 0) {
            fs::remove(entry_path);
            fs::copy_file(
                link_destination,
                entry_path
            );
            continue;
        }

        std::cerr 
            << "Link destination:\n"
            << link_destination_str << "\n"
            << "is absolute and points outside of origin output dir:\n"
            << package_output_origin_dir_str << "\n"
            << "or ports dir:\n"
            << port_dir_str
            << std::endl;

        return 127;
    }

    return 0;
}