#include <mero/Language.hpp>

namespace mero {

    std::ostream &operator<<(std::ostream &os, Language language)
    {
        switch (language)
        {
            case Language::Markdown: os << "Markdown"; break;
            case Language::CStyle: os << "CStyle"; break;
            case Language::Rust: os << "Rust"; break;
            case Language::Zig: os << "Zig"; break;
            case Language::Ruby: os << "Ruby"; break;
            case Language::Lua: os << "Lua"; break;
        }
        return os;
    }

    std::optional<Language> language(const std::string_view &extension)
    {
        if (extension == ".md") return Language::Markdown;
        if (extension == ".hpp" || extension == ".cpp" || extension == ".h" || extension == ".c") return Language::CStyle;
        if (extension == ".rs") return Language::Rust;
        if (extension == ".zig") return Language::Zig;
        if (extension == ".rb") return Language::Ruby;
        if (extension == ".lua") return Language::Lua;
        return std::nullopt;
    }

} // namespace mero
