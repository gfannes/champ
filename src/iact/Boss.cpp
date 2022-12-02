#include <iact/Boss.hpp>

#include <gubg/mss.hpp>

namespace iact {

    Boss::Boss(data::Boss &data, show::Boss &show)
        : data_(data), show_(show)
    {
        show_.set_location(data_.location());
    }

    bool Boss::process(std::optional<char> ch)
    {
        MSS_BEGIN(bool);
        if (ch)
        {
            switch (*ch)
            {
                case 'q':
                    signals.quit.emit();
                    break;
                case 'h':
                    data_.to_root();
                    show_.set_location(data_.location());
                    break;
            }
        }
        else
        {
            show_.set_selection(data_.selection());
        }

        MSS_END();
    }

} // namespace iact
