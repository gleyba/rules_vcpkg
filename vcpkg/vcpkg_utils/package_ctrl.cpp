#include <string>
#include <string_view>
#include <vector>
#include <fstream>
#include <optional>
#include <filesystem>

#include "package_ctrl.hpp"

namespace fs = std::filesystem;

std::optional<std::string> parse_if_needed_line(const std::string& line, std::string_view prefix) {
    if (line.find(prefix) != 0) {
        return std::nullopt;
    }

    return line.substr(prefix.size());
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
        if (line.empty()) {
            continue;
        }

        if (line.find("Package: ") == 0) {
            if (name) {
                // Probably parsing feature now, need to add installed mark
                status_data.push_back("Status: install ok installed");  
                status_data.push_back("");  
            } else {
                name = parse_if_needed_line(line, "Package: ");
            }
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
