#include <data/Boss.hpp>

namespace data {

    Boss::Boss()
        : location_(std::filesystem::current_path())
    {
    }

    std::string Boss::location() const
    {
        return location_.string();
    }

    std::vector<std::string> Boss::selection() const
    {
        std::vector<std::string> vec;
        for (const auto &dir_entry : std::filesystem::directory_iterator{location_})
        {
            vec.push_back(dir_entry.path().filename());
        }
        return vec;
    }

    void Boss::to_root()
    {
        location_ = location_.parent_path();
    }

} // namespace data