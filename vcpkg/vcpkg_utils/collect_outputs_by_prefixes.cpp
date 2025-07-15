#include <string>
#include <vector>

#include "copy_sources.hpp"

namespace fs = std::filesystem;

#include <iostream>

int main(int argc, char ** argv) {
    fs::path output_dir { argv[1] };

    std::vector<fs::path> inputs (
        argv + 2,
        argv + argc
    );

    fs::create_directories(output_dir);

    for (const fs::path& input: inputs) {
        if (!fs::exists(input)) {
            continue;
        }

        copy_sources(
            input,
            output_dir,
            false,
            false
        );
    }

    return 0;
}