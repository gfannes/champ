#ifndef HEADER_apm_Scanner_hpp_ALREADY_INCLUDED
#define HEADER_apm_Scanner_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>

#include <rubr/mss.hpp>

#include <cstdint>
#include <string>
#include <vector>
#include <ostream>

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
    std::ostream &operator<<(std::ostream &os, Symbol symbol);

    Symbol parse_symbol(char ch);

    // Smaller data goes faster
    struct Token
    {
        const char *begin;
        std::uint16_t size;
        Symbol symbol;
    };
    std::ostream &operator<<(std::ostream &os, const Token &token);
    using Tokens = std::vector<Token>;

    class Scanner
    {
    public:
        template <typename Builder>
        ReturnCode init(Builder builder)
        {
            MSS_BEGIN(ReturnCode);
            MSS(builder(content_));
            MSS_END();
        }

        ReturnCode scan();

        const Tokens &tokens() const { return tokens_; }

    private:
        std::string content_;
        Tokens tokens_;
    };

} // namespace amp

#endif
