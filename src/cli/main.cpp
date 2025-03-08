#include <cli/App.hpp>

#include <rubr/mss.hpp>

#include <iostream>

namespace cli {
    ReturnCode main(int argc, const char **argv)
    {
        MSS_BEGIN(ReturnCode);

        cli::Options options;
        MSS(options.parse(argc, argv), std::cerr << "Could not parse CLI optinos" << std::endl);

        if (options.print_help)
        {
            std::cout << options.help();
            MSS_RETURN_OK();
        }

        cli::App app{options};
        MSS(app.run());

        MSS_END();
    }

} // namespace cli

int main(int argc, const char **argv)
{
    const auto rc = cli::main(argc, argv);
    if (rc != ReturnCode::Ok)
    {
        std::cerr << "Something went wrong" << std::endl;
        return -1;
    }

    return 0;
}
