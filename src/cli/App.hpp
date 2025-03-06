#include <cli/Options.hpp>

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
    };

} // namespace cli
