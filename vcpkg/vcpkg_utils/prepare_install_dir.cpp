#include <string.h>

#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <iostream>
#include <optional>
#include <algorithm>
#include <filesystem>

#include "package_ctrl.hpp"
#include "copy_sources.hpp"

namespace fs = std::filesystem;

std::vector<package_control_t> read_packages(const fs::path& packages_outputs_list_path) {
    std::vector<package_control_t> packages_ctrls;
    std::ifstream list_ifs(packages_outputs_list_path);
    std::string line;
    while (std::getline(list_ifs, line)) {
        packages_ctrls.push_back(read_package_control(line));
    }
    return packages_ctrls;
}

// void write_manifest(const fs::path& vcpkg_meta_dir, const fs::path& manifest_path) {
//     std::ofstream manifest_info(vcpkg_meta_dir / "manifest-info.json");
//     manifest_info << "{\n" 
//         << "  \"manifest-path\": "
//         << manifest_path.lexically_relative(vcpkg_meta_dir)
//         << "\n"
//         << "}\n";
//     manifest_info.close();
// }

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

void write_listing(const fs::path& vcpkg_info_dir, const package_control_t& ctrl, const std::vector<std::string>& listing) {
    std::string listing_filename = ctrl.name + "_" + ctrl.version + "_" + ctrl.architecture + ".list";
    fs::path listing_out = vcpkg_info_dir / listing_filename;
    
    std::ofstream listing_ofs(listing_out);
    for (const std::string& path: listing) {
        listing_ofs << ctrl.architecture << "/" << path << "\n";
    }
    listing_ofs.close();
}

void prepare_install_dir(
    const fs::path& install_dir,
    // const fs::path& manifest_path,
    const fs::path& packages_outputs_list_path,
    bool reuse_install_dirs
) {
    auto packages_ctrls = read_packages(packages_outputs_list_path);
    fs::path vcpkg_meta_dir = install_dir / "vcpkg"; 
    fs::create_directories(vcpkg_meta_dir);
    // write_manifest(vcpkg_meta_dir, manifest_path);
    write_status(vcpkg_meta_dir, packages_ctrls);

    fs::path vcpkg_info_dir = vcpkg_meta_dir / "info";
    fs::create_directories(vcpkg_info_dir);

    for (const auto& ctrl: packages_ctrls) {
        std::vector<std::string> listing;
        for (const auto& dir_entry : fs::recursive_directory_iterator{ctrl.output_dir}) {
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
                if (fs::exists(install_path)) {
                    if (reuse_install_dirs) {
                        continue;
                    }
                    throw std::runtime_error("File at path '" + relative_path.string() + "' already exists in install dir");
                }

                fs::create_symlink(fs::absolute(entry_path), install_path);
            }
        }
        
        write_listing(vcpkg_info_dir, ctrl, listing);
    }
}

bool ends_with(const std::string& s, const std::string& suffix) {
    return s.rfind(suffix) == (s.size() - suffix.size());
}

const std::string s_venv_postfix = "-venv";

std::optional<fs::path> prepare_build_root(
    const fs::path& buildtrees_root, 
    const fs::path& buildtrees_tmp,
    bool has_sources_override,
    bool reuse_install_dirs
) {
    fs::copy_options co = reuse_install_dirs
        ? fs::copy_options::update_existing
        : fs::copy_options::none;

    std::optional<fs::path> sources_location;
    for (const auto& package_buildtree_entry: fs::directory_iterator { buildtrees_root }) {
        for (const auto& package_inner_entry:  fs::directory_iterator { package_buildtree_entry.path() }) {
            fs::path entry_path = package_inner_entry.path();
            if (entry_path.filename() == "src") {
                for (const auto& src_entry: fs::directory_iterator {entry_path}) {
                    fs::path src = src_entry.path();
                    if (src.extension() != ".clean") {
                        continue;
                    }
                    
                    fs::path dst =  buildtrees_tmp / src.lexically_relative(buildtrees_root);
                    dst.replace_extension("");
                    sources_location = dst;
                    if (has_sources_override) {
                        continue;
                    }

                    copy_sources(src, dst, co, false);
                }
            } else if (ends_with(entry_path.string(), s_venv_postfix)) {
                fs::path dst =  buildtrees_tmp / entry_path.lexically_relative(buildtrees_root);
                copy_sources(entry_path, dst, co, true);
            }
        }
    }

    return sources_location;
}

int main(int argc, char ** argv) {
    fs::path buildtrees_tmp { argv[1] };
    fs::path install_dir = buildtrees_tmp / "install";
    fs::path packages_outputs_list_path { argv[2] };
    fs::path buildtrees_root { argv[3] };
    std::string override_sources { argv[4] };
    bool reuse_install_dirs = strcmp(argv[5], "1") == 0;

    prepare_install_dir(
        install_dir, 
        packages_outputs_list_path,
        reuse_install_dirs
    );

    bool has_sources_override = override_sources != "nope";

    auto sources_location = prepare_build_root(
        buildtrees_root, 
        buildtrees_tmp,
        has_sources_override,
        reuse_install_dirs
    );

    if (has_sources_override) {
        if (!sources_location) {
            throw std::runtime_error("Can't detect sources location for sources override");
        }

        copy_sources(
            override_sources,
            sources_location.value(),
            fs::copy_options::update_existing,
            false
        );
    }

    return 0;
}
