#include <amp/Scanner.hpp>

#include <rubr/mss.hpp>

#include <array>
#include <utility>

namespace amp {

    ReturnCode Scanner::operator()(std::string_view sv)
    {
        MSS_BEGIN(ReturnCode);

        tokens_.resize(0);

        if (sv.empty())
            MSS_RETURN_OK();

        Token token{.begin = sv.data(), .size = 1, .symbol = parse_symbol(sv[0])};

        for (const auto ch : sv.substr(1))
        {
            const auto my_symbol = parse_symbol(token.begin[token.size]);

            if (my_symbol != token.symbol)
                tokens_.push_back(std::exchange(token, Token{.begin = token.begin + token.size, .size = 0, .symbol = my_symbol}));

            ++token.size;
        }

        tokens_.push_back(token);

        MSS_END();
    }

    struct Table
    {
        std::array<Symbol, 256> table;
        Table()
        {
            for (auto &symbol : table)
                symbol = Symbol::Word;
            table[' '] = Symbol::Space;
            table['!'] = Symbol::Exclamation;
            table['?'] = Symbol::Questionmark;
            table['|'] = Symbol::Pipe;
            table['@'] = Symbol::At;
            table['#'] = Symbol::Hashtag;
            table['$'] = Symbol::Dollar;
            table['%'] = Symbol::Percent;
            table['^'] = Symbol::Hat;
            table['&'] = Symbol::Ampersand;
            table['*'] = Symbol::Star;
            table['('] = Symbol::OpenParens;
            table[')'] = Symbol::CloseParens;
            table['['] = Symbol::OpenSquare;
            table[']'] = Symbol::CloseSquare;
            table['{'] = Symbol::OpenCurly;
            table['}'] = Symbol::CloseCurly;
            table['<'] = Symbol::OpenAngle;
            table['>'] = Symbol::CloseAngle;
            table['~'] = Symbol::Tilde;
            table['+'] = Symbol::Plus;
            table['-'] = Symbol::Minus;
            table['='] = Symbol::Equal;
            table[':'] = Symbol::Colon;
            table['_'] = Symbol::Underscore;
            table['.'] = Symbol::Dot;
            table[','] = Symbol::Comma;
            table[';'] = Symbol::Semicolon;
            table['\''] = Symbol::SingleQuote;
            table['"'] = Symbol::DoubleQuote;
            table['`'] = Symbol::Backtick;
            table['/'] = Symbol::Slash;
            table['\\'] = Symbol::BackSlash;
            table['\n'] = Symbol::Newline;
            table['\r'] = Symbol::CarriageReturn;
        }
    };
    static Table s_table;

    Symbol parse_symbol(char ch)
    {
        return s_table.table[ch];
    }

} // namespace amp
