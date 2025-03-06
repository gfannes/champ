#ifndef HEADER_cli_Options_hpp_ALREADY_INCLUDED
#define HEADER_cli_Options_hpp_ALREADY_INCLUDED

#include <cli/ReturnCode.hpp>

#include <string>
#include <optional>

namespace cli {
    class Options
    {
    public:
        std::string exe_name;

        bool print_help = false;
        std::optional<std::string> folder;

        ReturnCode parse(int argc, const char **argv);

        std::string help() const;
    private:
    };
} // namespace app

#endif
