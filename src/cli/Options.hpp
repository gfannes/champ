#ifndef HEADER_cli_Options_hpp_ALREADY_INCLUDED
#define HEADER_cli_Options_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>

#include <string>
#include <optional>
#include <vector>

namespace cli {

    enum class Command{
        ListFiles,
    };

    class Options
    {
    public:
        std::string exe_name;

        bool print_help = false;
        std::vector<std::string> groves;
        std::optional<Command> command;
        bool print_filename = false;
        bool do_scan = false;
        bool do_parse = false;

        ReturnCode parse(int argc, const char **argv);

        std::string help() const;
    private:
    };

} // namespace app

#endif
