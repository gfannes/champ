#include <cli/Options.hpp>

#include <gubg/cli/Range.hpp>
#include <gubg/mss.hpp>

namespace cli { 

bool Options::parse(int argc, const char **argv)
{
    MSS_BEGIN(bool);

    gubg::cli::Range range{argc, argv};
    
    MSS(range.pop(exe_name));
    
    for (std::string arg; range.pop(arg); )
    {
    }

    MSS_END();
}

} 