#include <show/Boss.hpp>

#include <gubg/mss.hpp>
#include <gubg/tui.hpp>

#include <iostream>

namespace show {

    bool Boss::setup()
    {
        MSS_BEGIN(bool);
        MSS(gubg::tui::get_size(width_, height_));
        MSS_END();
    }

    bool Boss::draw()
    {
        MSS_BEGIN(bool);
        std::cout << width_ << " x " << height_ << std::endl;
        MSS_END();
    }

} // namespace show