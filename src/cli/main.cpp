#include <cli/App.hpp>

#include <gubg/mss.hpp>

#include <iostream>

int main(int argc, const char **argv)
{
    MSS_BEGIN(int);

    cli::Options options;
    MSS(options.parse(argc, argv));

    if (options.print_help)
    {
        std::cout << options.help();
        MSS_RETURN_OK();
    }

    cli::App app{options};

    MSS(app.run());

    MSS_END();
}
