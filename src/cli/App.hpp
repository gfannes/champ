#ifndef HEADER_cli_App_hpp_ALREAD_INCLUDED
#define HEADER_cli_App_hpp_ALREAD_INCLUDED

#include <cli/Options.hpp>
#include <iact/Boss.hpp>

#include <optional>

namespace cli {

    class App
    {
    public:
        App(const Options &options)
            : options_(options) {}

        bool run();

    private:
        bool setup_();
        bool mainloop_();

        const Options &options_;

        bool quit_ = false;

        std::optional<data::Boss> data_;
        std::optional<show::Boss> show_;
        std::optional<iact::Boss> iact_;
    };

} // namespace cli

#endif
