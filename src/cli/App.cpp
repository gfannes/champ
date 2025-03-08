#include <cli/App.hpp>

#include <amp/Scanner.hpp>

#include <rubr/fs/Walker.hpp>
#include <rubr/macro/capture.hpp>
#include <rubr/mss.hpp>
#include <rubr/profile/Stopwatch.hpp>

#include <chrono>
#include <iostream>

namespace cli {

    ReturnCode App::run()
    {
        MSS_BEGIN(ReturnCode);

        const rubr::profile::Stopwatch sw;

        if (options_.folder)
            MSS(list_files_());

        std::cout << "Elapse: " << sw.elapse<std::chrono::milliseconds>() << std::endl;

        MSS_END();
    }

    ReturnCode App::list_files_() const
    {
        MSS_BEGIN(ReturnCode);

        using Walker = rubr::fs::Walker;
        MSS(!!options_.folder, std::cerr << "Expected folder to be set" << std::endl);
        Walker walker{Walker::Config{.basedir = *options_.folder}};

        std::size_t file_count = 0;
        std::size_t byte_count = 0;

        std::string content;
        amp::Scanner scanner;

        MSS(walker([&](const auto &fp) {
            MSS_BEGIN(bool);
            ++file_count;
            // std::cout << fp.native() << std::endl;
            // MSS(rubr::fs::read(content, fp));
            // byte_count += content.size();

            // MSS(scanner(content));

            MSS_END();
        }));

        std::cout << C(file_count) C(byte_count / 1024 / 1024) << std::endl;

        MSS_END();
    }

} // namespace cli
