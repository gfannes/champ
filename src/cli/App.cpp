#include <cli/App.hpp>

#include <gubg/mss.hpp>

namespace cli {

    bool App::run()
    {
        MSS_BEGIN(bool);
        while (mainloop_())
        {
        }
        MSS_END();
    }

    // Privates
    bool App::mainloop_()
    {
        MSS_BEGIN(bool);
        MSS_END();
    }

} // namespace cli
