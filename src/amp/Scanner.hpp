#ifndef HEADER_apm_Scanner_hpp_ALREADY_INCLUDED
#define HEADER_apm_Scanner_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>

#include <cstdint>
#include <string_view>
#include <variant>
#include <vector>

namespace amp {

    enum class Kind : std::uint8_t
    {
        None,

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

    Kind parse_symbol(char ch);

    struct Symbol
    {
        Kind kind;
        std::uint16_t count = 0;
    };
    using Token = std::variant<Symbol, std::string>;

    class Scanner
    {
    public:
        ReturnCode operator()(std::string_view sv);

    private:
        std::vector<Token> tokens_;
    };

} // namespace amp

#endif
