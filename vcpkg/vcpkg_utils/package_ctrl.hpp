#pragma once

#include <string>
#include <vector>
#include <filesystem>

struct package_control_t {
    const std::string name;
    const std::string version;
    const std::string architecture;
    const std::vector<std::string> status_data;
    const std::filesystem::path output_dir;
};

package_control_t read_package_control(const std::filesystem::path& package_output_dir);