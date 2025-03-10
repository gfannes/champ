#ifndef HEADER_cli_Grove_hpp_ALREADY_INCLUDED
#define HEADER_cli_Grove_hpp_ALREADY_INCLUDED

#include <string>
#include <filesystem>
#include <optional>
#include <vector>

namespace cli {

    struct Grove
    {
        std::string name;
        std::filesystem::path root;
        std::vector<std::string> extensions;
        std::optional<std::size_t> max_size;
    };

} // namespace cli

#endif
