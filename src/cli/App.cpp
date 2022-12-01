#include <cli/App.hpp>

#include <gubg/mss.hpp>
#include <gubg/tui.hpp>

namespace cli {

    bool App::run()
    {
        MSS_BEGIN(bool);

        bool quit = false;
        iact_.signals.quit.connect([&]() { quit = true; });

        MSS(setup_());

        while (!quit)
        {
            MSS(mainloop_());
        }

        MSS_END();
    }

    // Privates
    bool App::setup_()
    {
        MSS_BEGIN(bool);

        show_.setup();

        MSS_END();
    }

    bool App::mainloop_()
    {
        MSS_BEGIN(bool);

        MSS(show_.draw());

        char ch;
        MSS(gubg::tui::get_char(ch));
        MSS(iact_.process(ch));

        MSS_END();
    }

} // namespace cli
