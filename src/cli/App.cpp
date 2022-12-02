#include <cli/App.hpp>

#include <gubg/mss.hpp>

namespace cli {

    bool App::run()
    {
        MSS_BEGIN(bool);

        MSS(setup_());

        while (!quit_)
        {
            MSS(mainloop_());
        }

        MSS_END();
    }

    // Privates
    bool App::setup_()
    {
        MSS_BEGIN(bool);

        data_.emplace();
        show_.emplace();
        iact_.emplace(*data_, *show_);

        iact_->signals.quit.connect([&]() { quit_ = true; });

        MSS_END();
    }

    bool App::mainloop_()
    {
        MSS_BEGIN(bool);

        MSS(!!show_);
        auto &show = *show_;

        MSS(!!iact_);
        auto &iact = *iact_;

        MSS(show.draw());

        std::optional<char> ch;
        MSS(show.read_char(ch));

        MSS(iact.process(ch));

        MSS_END();
    }

} // namespace cli
