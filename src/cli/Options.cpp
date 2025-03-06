#include <cli/Options.hpp>

#include <rubr/cli/Range.hpp>
#include <rubr/mss.hpp>

#include <iostream>
#include <sstream>

namespace cli {

    ReturnCode Options::parse(int argc, const char **argv)
    {
        MSS_BEGIN(ReturnCode);

        rubr::cli::Range r{argc, argv};

        MSS(r.pop(exe_name));

        for (std::string arg; r.pop(arg);)
        {
            auto is = [&](const char *sh, const char *lh) {
                return arg == sh || arg == lh;
            };

            if (false) {}
            else if (is("-h", "--help"))
                print_help = true;
            else if (is("-f", "--folder"))
                MSS(r.pop(folder.emplace()));
            else
                MSS(false, std::cerr << "Unknown CLI argument '" << arg << "'" << std::endl);
        }

        MSS_END();
    }

    std::string Options::help() const
    {
        std::ostringstream oss;
        oss << "Help for '" << exe_name << "'" << std::endl;
        oss << "    -h  --help    Print this help" << std::endl;
        oss << "    -f  --folder  Folder" << std::endl;
        oss << "Developed by Geert Fannes" << std::endl;
        return oss.str();
    }

} // namespace cli
