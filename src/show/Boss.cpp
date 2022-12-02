#include <show/Boss.hpp>

#include <gubg/mss.hpp>
#include <gubg/string/concat.hpp>

#include <iostream>

namespace show {

    Boss::Boss()
    {
        setup_();
        location_ = "Location";
        status_ = "Welcome to Champetter";
    }

    Boss::~Boss()
    {
        if (term_)
        {
            term_->clear();
            term_->print("Done\n", {0, 0});
        }
    }

    bool Boss::read_char(std::optional<char> &ch)
    {
        MSS_BEGIN(bool);
        MSS(!!term_);
        auto &term = *term_;
        MSS(term.read(ch));
        MSS_END();
    }

    bool Boss::draw()
    {
        MSS_BEGIN(bool);
        MSS(!!term_);
        auto &term = *term_;

        term.clear();

        for (auto ix0 = 0u; ix0 < std::min<unsigned int>(size_.height - 2, selection_.size()); ++ix0)
        {
            gubg::tui::Position pos{
                .row = ix0 + 1,
                .col = 0,
            };
            term.print(selection_[ix0], pos);
        }

        term.print(location_, {0, 0});

        const auto str = gubg::string::concat(status_, ' ', iteration_++);
        term.print(str, {size_.height - 1, size_.width - (unsigned int)str.size()});

        MSS_END();
    }

    // Privates
    bool Boss::setup_()
    {
        MSS_BEGIN(bool);

        gubg::tui::Terminal term;
        MSS(term.get(size_));
        term.clear();

        term_.emplace(std::move(term));

        MSS_END();
    }

} // namespace show