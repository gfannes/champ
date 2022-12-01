#ifndef HEADER_iact_Boss_hpp_ALREAD_INCLUDED
#define HEADER_iact_Boss_hpp_ALREAD_INCLUDED

#include <show/Boss.hpp>

#include <gubg/Signal.hpp>

namespace iact {

    class Boss
    {
    public:
        Boss(show::Boss &show)
            : show_(show) {}

        struct Signals
        {
            gubg::Signal<> quit;
        };
        Signals signals;

        bool process(char ch);

    private:
        show::Boss &show_;
    };

} // namespace iact

#endif
