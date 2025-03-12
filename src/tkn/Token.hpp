#ifndef HEADER_tkn_Token_hpp_ALREADY_INCLUDED
#define HEADER_tkn_Token_hpp_ALREADY_INCLUDED

#include <str/Range.hpp>

#include <cstdint>
#include <ostream>
#include <vector>

namespace tkn {

    enum class Symbol : std::uint8_t
    {
        Word,

        Space,
        Exclamation,
        Questionmark,
        Pipe,
        At,
        Hashtag,
        Dollar,
        Percent,
        Hat,
        Ampersand,
        Star,
        OpenParens,
        CloseParens,
        OpenSquare,
        CloseSquare,
        OpenCurly,
        CloseCurly,
        OpenAngle,
        CloseAngle,
        Tilde,
        Plus,
        Minus,
        Equal,
        Colon,
        Underscore,
        Dot,
        Comma,
        Semicolon,
        SingleQuote,
        DoubleQuote,
        Backtick,
        Slash,
        BackSlash,
        Newline,
        CarriageReturn,
    };
    std::ostream &operator<<(std::ostream &os, Symbol symbol);

    struct Token
    {
        str::Range range;
        Symbol symbol;
    };
    std::ostream &operator<<(std::ostream &os, const Token &token);

    using Tokens = std::vector<Token>;

} // namespace tkn

#endif
