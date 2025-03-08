#ifndef HEADER_apm_Scanner_hpp_ALREADY_INCLUDED
#define HEADER_apm_Scanner_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>

#include <cstdint>
#include <string_view>
#include <vector>

namespace amp {

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

    Symbol parse_symbol(char ch);

    // Smaller data goes faster
    struct Token
    {
        const char *begin;
        std::uint16_t size;
        Symbol symbol;
    };

    class Scanner
    {
    public:
        ReturnCode operator()(std::string_view sv);

    private:
        std::vector<Token> tokens_;
    };

} // namespace amp

#endif
