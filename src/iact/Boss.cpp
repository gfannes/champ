#include <iact/Boss.hpp>

#include <gubg/mss.hpp>

namespace iact {

    bool Boss::process(char ch)
    {
        MSS_BEGIN(bool);
        switch (ch)
        {
            case 'q':
                signals.quit.emit();
                break;
        }
        MSS_END();
    }

} // namespace iact
