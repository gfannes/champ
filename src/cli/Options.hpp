#ifndef HEADER_cli_Options_hpp_ALREAD_INCLUDED
#define HEADER_cli_Options_hpp_ALREAD_INCLUDED

#include <string>

namespace cli {
    class Options 
    {
    public:
    bool parse(int argc, const char **argv);
    
    std::string exe_name;
    
    bool print_help = false;

    private:
    };
} 

#endif

