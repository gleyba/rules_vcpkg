#include <filesystem>
#include <string>
#include <fstream>
#include <sstream>
#include <iostream>
#include <algorithm>


std::string get_relative_manifest_path(const std::string& manifest_path, const std::string& install_dir) {
    std::string::difference_type n = std::count(install_dir.begin(), install_dir.end(), '/') + 1;
    std::ostringstream os;
    for(int i = 0; i < n; ++i)
        os << "../";

    os << manifest_path;

    return os.str();
}

int main(int argc, char ** argv, char **envp) {
    std::string install_dir = argv[1];
    std::string triplet = argv[2];
    std::string manifest_path = argv[3];

    std::filesystem::create_directories(install_dir);
    std::ofstream manifest_info(install_dir + "/manifest-info.json");
    manifest_info << "{\n" 
        << "  \"manifest-path\": \""
        << get_relative_manifest_path(manifest_path, install_dir)
        << "\"\n"
        << "}\n";
    manifest_info.close();

    // TODO: fill with dependencies
    std::ofstream status(install_dir + "/status");
    status << "\n";
    status.close();

    // std::cout << "Current path is " << std::filesystem::current_path() << std::endl;
    // std::cout << "Preparing install directory: " << install_dir << std::endl;
    // std::cout << "Triplet: " << triplet << std::endl;
    // std::cout << "Manifest path: " << get_relative_manifest_path(manifest_path, install_dir) << std::endl;

    return 0;
}