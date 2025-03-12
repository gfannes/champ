#include <tkn/Scanner.hpp>

#include <rubr/mss.hpp>

#include <utility>

namespace tkn {

    ReturnCode Scanner::scan()
    {
        MSS_BEGIN(ReturnCode);

        tokens_.resize(0);

        std::string_view sv = content_;

        if (sv.empty())
            MSS_RETURN_OK();

        Token token{.range = str::Range{.ix = 0, .size = 1}, .symbol = parse_symbol(sv[0])};

        for (const auto ch : sv.substr(1))
        {
            const auto my_symbol = parse_symbol(ch);

            if (my_symbol != token.symbol)
                tokens_.push_back(std::exchange(token, Token{.range = str::Range{.ix = token.range.ix + token.range.size, .size = 0}, .symbol = my_symbol}));

            ++token.range.size;
        }

        tokens_.push_back(token);

        MSS_END();
    }

    struct Table
    {
        std::array<Symbol, 128> table;
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

    // For performance, parse_symbol() must remain in same TU as Scanner::scan()
    Symbol parse_symbol(char ch)
    {
        return s_table.table[ch];
    }

} // namespace tkn
