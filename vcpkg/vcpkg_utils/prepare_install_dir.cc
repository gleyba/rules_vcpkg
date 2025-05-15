#include <filesystem>
#include <string>
#include <string_view>
#include <vector>
#include <fstream>
#include <sstream>
#include <iostream>
#include <optional>
#include <algorithm>

namespace fs = std::filesystem;

void write_manifest(const fs::path& vcpkg_meta_dir, const fs::path& manifest_path) {
    std::ofstream manifest_info(vcpkg_meta_dir / "manifest-info.json");
    manifest_info << "{\n" 
        << "  \"manifest-path\": "
        << manifest_path.lexically_relative(vcpkg_meta_dir)
        << "\n"
        << "}\n";
    manifest_info.close();
}

struct package_control_t {
    const std::string name;
    const std::string version;
    const std::string architecture;
    const std::vector<std::string> status_data;
    const fs::path output_dir;
};

void write_status(const fs::path& vcpkg_meta_dir, const std::vector<package_control_t>& packages_ctrls) {
    std::ofstream status_ofs(vcpkg_meta_dir / "status");
    for (const auto& ctrl: packages_ctrls) {
        for (const auto& status_line: ctrl.status_data) {
            status_ofs << status_line << "\n";
        }
        status_ofs << "\n";
    }
    status_ofs.close();
}

std::optional<std::string> parse_if_needed_line(const std::string& line, std::string_view prefix) {
    if (line.find(prefix) != 0) {
        return std::nullopt;
    }

    return line.substr(prefix.size());
}

void write_listing(const fs::path& vcpkg_info_dir, const package_control_t& ctrl, const std::vector<std::string>& listing) {
    std::string listing_filename = ctrl.name + "_" + ctrl.version + "_" + ctrl.architecture + ".list";
    fs::path listing_out = vcpkg_info_dir / listing_filename;
    
    std::ofstream listing_ofs(listing_out);
    for (const std::string& path: listing) {
        listing_ofs << ctrl.architecture << "/" << path << "\n";
    }
    listing_ofs.close();
}

package_control_t read_package_control(const fs::path& package_output_dir) {
    fs::path control_path = package_output_dir / "CONTROL";
    if (!fs::exists(control_path)) {
        throw std::runtime_error("Can't find CONTROL file in " + package_output_dir.string());
    }

    std::ifstream control_ifs { control_path };
    if (!control_ifs.is_open()) {
        throw std::runtime_error("Can't open " + control_path.string());
    }

    std::optional<std::string> name;
    std::optional<std::string> version;
    std::optional<std::string> architecture;
    std::vector<std::string> status_data;

    std::string line;
    while (std::getline(control_ifs, line)) {
        if (!name) {
            name = parse_if_needed_line(line, "Package: ");
        }

        if (!version) {
            version = parse_if_needed_line(line, "Version: ");
        }

        if (!architecture) {
            architecture = parse_if_needed_line(line, "Architecture: ");
        }

        status_data.push_back(std::move(line));
    }

    if (!name) {
        throw std::runtime_error("Can't parse package name from " + control_path.string());
    }

    if (!version) {
        throw std::runtime_error("Can't parse version from " + control_path.string());
    }

    status_data.push_back("Status: install ok installed");    

    return package_control_t {
        .name = std::move(name).value(),
        .version = std::move(version).value(),
        .architecture = std::move(architecture).value(),
        .status_data = std::move(status_data),
        .output_dir = package_output_dir,
    };
}

int main(int argc, char ** argv) {
    fs::path install_dir { argv[1] };
    fs::path manifest_path { argv[2] };

    std::vector<package_control_t> packages_ctrls;
    for (std::size_t i = 3; i < argc; ++i) {
        packages_ctrls.push_back(read_package_control({argv[i]}));
    }

    fs::path vcpkg_meta_dir = install_dir / "vcpkg"; 
    fs::create_directories(vcpkg_meta_dir);
    write_manifest(vcpkg_meta_dir, manifest_path);
    write_status(vcpkg_meta_dir, packages_ctrls);

    fs::path vcpkg_info_dir = vcpkg_meta_dir / "info";
    fs::create_directories(vcpkg_info_dir);

    for (const auto& ctrl: packages_ctrls) {
        std::vector<std::string> listing;
        for (auto const& dir_entry : fs::recursive_directory_iterator{ctrl.output_dir}) {
            auto entry_path = dir_entry.path();

            if (entry_path.filename() == "BUILD_INFO") {
                continue;
            }

            if (entry_path.filename() == "CONTROL") {
                continue;
            }

            auto relative_path = entry_path.lexically_relative(ctrl.output_dir);
            listing.push_back(relative_path);

            auto install_path = install_dir / ctrl.architecture / relative_path;

            if (dir_entry.is_directory()) {
                fs::create_directories(install_path);
            } else {
                // fs::create_symlink(entry_path, install_path);
                fs::copy_file(entry_path, install_path);
            }
        }
        
        write_listing(vcpkg_info_dir, ctrl, listing);
    }

    return 0;
}
