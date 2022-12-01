#include <cli/Options.hpp>
#include <util/log.hpp>

#include <gubg/cli/Range.hpp>
#include <gubg/mss.hpp>

#include <sstream>

namespace cli {

    bool Options::parse(int argc, const char **argv)
    {
        MSS_BEGIN(bool);

        gubg::cli::Range range{argc, argv};

        MSS(range.pop(exe_name));

        for (std::string arg; range.pop(arg);)
        {
            auto is = [&](const char *sh, const char *lh) { return arg == sh || arg == lh; };

            if (false) {}
            else if (is("-h", "--help")) { print_help = true; }
            else if (is("-V", "--verbose")) { MSS(range.pop(verbose_level)); }
            else
            {
                util::log::error() << "Unknown argument '" << arg << "'" << std::endl;
            }
        }

        MSS_END();
    }

    std::string Options::help() const
    {
        std::ostringstream oss;
        oss << exe_name << std::endl;
        oss << "    -h --help             Show this help" << std::endl;
        oss << "    -V --verbose  LEVEL   Set verbosity level" << std::endl;
        oss << "Written by Geert Fannes." << std::endl;
        return oss.str();
    }

} // namespace cli