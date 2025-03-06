#include <cli/App.hpp>

#include <rubr/fs/Walker.hpp>
#include <rubr/mss.hpp>

#include <iostream>
#include <chrono>

namespace cli {

    ReturnCode App::run()
    {
        MSS_BEGIN(ReturnCode);

        using Clock = std::chrono::system_clock;
        const auto start_ts = Clock::now();

        if (options_.folder)
            MSS(list_files_());

        const auto elapse = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now()-start_ts);
        std::cout << "Elapse: " << elapse << std::endl;

        MSS_END();
    }

    ReturnCode App::list_files_() const
    {
        MSS_BEGIN(ReturnCode);

        using Walker = rubr::fs::Walker;
        MSS(!!options_.folder, std::cerr << "Expected folder to be set" << std::endl);
        Walker walker{Walker::Config{.basedir = *options_.folder}};

        std::size_t count = 0;

        MSS(walker([&](const auto &fp) {
            MSS_BEGIN(bool);
            ++count;
            // std::cout << fp << std::endl;
            MSS_END();
        }));

        std::cout << "Filecount: " << count << std::endl;

        MSS_END();
    }

} // namespace cli
