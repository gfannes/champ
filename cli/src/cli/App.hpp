#ifndef HEADER_cli_App_hpp_ALREAD_INCLUDED
#define HEADER_cli_App_hpp_ALREAD_INCLUDED

#include <cli/Options.hpp>

namespace cli { 
    class App 
    {
    public:
        App(const Options &options): options_(options) {}

    private:
        const Options options_;
    };
} 

#endif

