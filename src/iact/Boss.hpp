#ifndef HEADER_iact_Boss_hpp_ALREAD_INCLUDED
#define HEADER_iact_Boss_hpp_ALREAD_INCLUDED

#include <show/Boss.hpp>

namespace iact { 
    class Boss 
    {
    public:
    Boss(show::Boss &show): show_(show) {}

    private:
    show::Boss &show_;

    };
} 

#endif

