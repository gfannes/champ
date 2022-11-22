#include <cli/Options.hpp>
#include <cli/App.hpp>

#include <gubg/mss.hpp>

#include <iostream>

int main(int argc, const char **argv)
{
    MSS_BEGIN(int);
    cli::Options options;
    
    cli::App app{options};
    std::cout << "Everything went OK" << std::endl;
    MSS_END();
    return 0;
}
