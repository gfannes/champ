#ifndef HEADER_amp_Language_hpp_ALREADY_INCLUDED
#define HEADER_amp_Language_hpp_ALREADY_INCLUDED

#include <optional>
#include <string_view>

namespace amp {

    enum class Language
    {
        Markdown,
        CStyle,
        Rust,
        Zig,
        Ruby,
        Lua,
    };

    inline std::optional<Language> language(const std::string_view &extension)
    {
        if (extension == ".md") return Language::Markdown;
        if (extension == ".hpp" || extension == ".cpp" || extension == ".h" || extension == ".c") return Language::CStyle;
        if (extension == ".rs") return Language::Rust;
        if (extension == ".zig") return Language::Zig;
        if (extension == ".rb") return Language::Ruby;
        if (extension == ".lua") return Language::Lua;
        return std::nullopt;
    }

} // namespace amp

#endif
