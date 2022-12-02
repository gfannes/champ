#ifndef HEADER_show_Boss_hpp_ALREAD_INCLUDED
#define HEADER_show_Boss_hpp_ALREAD_INCLUDED

#include <gubg/tui/Terminal.hpp>

#include <optional>
#include <vector>

namespace show {

    class Boss
    {
    public:
        Boss();
        ~Boss();

        bool read_char(std::optional<char> &);

        void set_location(const std::string &str) { location_ = str; }
        void set_status(const std::string &str) { status_ = str; }
        void set_selection(const std::vector<std::string> &vec) { selection_ = vec; }

        bool draw();

    private:
        bool setup_();

        std::optional<gubg::tui::Terminal> term_;
        gubg::tui::Terminal::CharSize size_;
        unsigned int iteration_ = 0u;

        std::string location_;
        std::string status_;
        std::vector<std::string> selection_;
    };

} // namespace show

#endif
