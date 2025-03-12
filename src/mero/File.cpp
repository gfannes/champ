#include <mero/File.hpp>

namespace mero {

    void File::init(Language language, const std::string_view &content)
    {
        language_ = language;
        content_ = content;
    }

    std::optional<Language> File::language() const
    {
        return language_;
    }

    void File::write(std::ostream &os) const
    {
        os << "[File]";
        if (const auto l = language_; !!l)
            os << "(" << *l << ")";
        os << "{\n";
        for (const auto &node : root().childs())
        {
            node.write(os, content_);
            os << std::endl;
        }
        os << "}";
    }

} // namespace mero
