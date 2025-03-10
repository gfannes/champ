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

        MSS(config_.init(options_));

        const rubr::profile::Stopwatch sw;

        if (options_.command)
        {
            switch (*options_.command)
            {
                case Command::ListFiles:
                    MSS(list_files_());
                    break;
            }
        }

        std::cout << "Elapse: " << sw.elapse<std::chrono::milliseconds>() << std::endl;

        MSS_END();
    }

    ReturnCode App::list_files_() const
    {
        MSS_BEGIN(ReturnCode);

        std::size_t file_count = 0;
        std::size_t byte_count = 0;

        for (const auto &grove : config_.groves)
        {
            using Walker = rubr::fs::Walker;
            Walker walker{Walker::Config{.basedir = grove.root}};

            std::string content;
            amp::Scanner scanner;

            MSS(walker([&](const std::filesystem::path &fp) {
                MSS_BEGIN(bool);

                bool do_process = true;

                if (do_process && grove.max_size)
                    do_process = std::filesystem::file_size(fp) <= *grove.max_size;
                if (do_process && !grove.extensions.empty())
                    do_process = std::any_of(grove.extensions.begin(), grove.extensions.end(), [&](const auto &ext) { return fp.native().ends_with(ext); });

                if (do_process)
                {
                    ++file_count;
                    std::cout << fp.native() << std::endl;
                    MSS(rubr::fs::read(content, fp));
                    byte_count += content.size();

                    if (options_.do_scan)
                        MSS(scanner(content));
                }

                MSS_END();
            }));
        }

        std::cout << C(file_count) C(byte_count / 1024 / 1024) << std::endl;

        MSS_END();
    }

} // namespace cli
