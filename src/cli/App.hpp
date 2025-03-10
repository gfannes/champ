#include <cli/Options.hpp>
#include <cli/Config.hpp>

namespace cli {

    class App
    {
    public:
        App(const Options &options)
            : options_(options) {}

        ReturnCode run();

    private:
        ReturnCode list_files_() const;

        const Options &options_;
        Config config_;
    };

} // namespace cli
