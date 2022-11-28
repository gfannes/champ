#ifndef HEADER_cli_App_hpp_ALREAD_INCLUDED
#define HEADER_cli_App_hpp_ALREAD_INCLUDED

#include <cli/Options.hpp>
#include <iact/Boss.hpp>

namespace cli { 
    class App 
    {
    public:
        App(const Options &options): options_(options) {}
    
        bool run();

    private:
        bool mainloop_();

        const Options &options_;
    
        show::Boss show_;
        iact::Boss iact_{show_};
    };
} 

#endif

