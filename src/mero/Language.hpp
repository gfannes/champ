#ifndef HEADER_mero_Language_hpp_ALREADY_INCLUDED
#define HEADER_mero_Language_hpp_ALREADY_INCLUDED

#include <optional>
#include <string_view>
#include <ostream>

namespace mero {

    enum class Language
    {
        Markdown,
        CStyle,
        Rust,
        Zig,
        Ruby,
        Lua,
    };

    std::ostream &operator<<(std::ostream &os, Language language);

    std::optional<Language> language(const std::string_view &extension);

} // namespace mero

#endif
