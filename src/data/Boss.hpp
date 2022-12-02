#ifndef HEADER_data_Boss_hpp_ALREAD_INCLUDED
#define HEADER_data_Boss_hpp_ALREAD_INCLUDED

#include <string>
#include <vector>
#include <filesystem>

namespace data {

    class Boss
    {
    public:
        Boss();

        std::string location() const;
        std::vector<std::string> selection() const;

        void to_root();

    private:
        std::filesystem::path location_;
    };

} // namespace data

#endif
