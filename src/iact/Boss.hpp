#ifndef HEADER_iact_Boss_hpp_ALREAD_INCLUDED
#define HEADER_iact_Boss_hpp_ALREAD_INCLUDED

#include <data/Boss.hpp>
#include <show/Boss.hpp>

#include <gubg/Signal.hpp>

namespace iact {

    class Boss
    {
    public:
        Boss(data::Boss &, show::Boss &show);

        struct Signals
        {
            gubg::Signal<> quit;
        };
        Signals signals;

        bool process(std::optional<char> ch);

    private:
        data::Boss &data_;
        show::Boss &show_;
    };

} // namespace iact

#endif
