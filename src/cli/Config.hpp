#ifndef HEADER_cli_Config_hpp_ALREADY_INCLUDED
#define HEADER_cli_Config_hpp_ALREADY_INCLUDED

#include <cli/Grove.hpp>
#include <cli/Options.hpp>

#include <ReturnCode.hpp>

#include <rubr/mss.hpp>

#include <vector>

namespace cli {

    struct Config
    {
        std::vector<Grove> groves;

        ReturnCode init(const Options &options);
    };

} // namespace cli

#endif
