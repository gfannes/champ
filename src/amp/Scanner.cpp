#include <amp/Scanner.hpp>

#include <rubr/mss.hpp>

#include <array>
#include <utility>

namespace amp {

    ReturnCode Scanner::scan()
    {
        MSS_BEGIN(ReturnCode);

        tokens_.resize(0);

        std::string_view sv = content_;

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

    std::ostream &operator<<(std::ostream &os, Symbol symbol)
    {
        switch (symbol)
        {
            case Symbol::Word: os << "Word"; break;
            case Symbol::Space: os << "Space"; break;
            case Symbol::Exclamation: os << "Exclamation"; break;
            case Symbol::Questionmark: os << "Questionmark"; break;
            case Symbol::Pipe: os << "Pipe"; break;
            case Symbol::At: os << "At"; break;
            case Symbol::Hashtag: os << "Hashtag"; break;
            case Symbol::Dollar: os << "Dollar"; break;
            case Symbol::Percent: os << "Percent"; break;
            case Symbol::Hat: os << "Hat"; break;
            case Symbol::Ampersand: os << "Ampersand"; break;
            case Symbol::Star: os << "Star"; break;
            case Symbol::OpenParens: os << "OpenParens"; break;
            case Symbol::CloseParens: os << "CloseParens"; break;
            case Symbol::OpenSquare: os << "OpenSquare"; break;
            case Symbol::CloseSquare: os << "CloseSquare"; break;
            case Symbol::OpenCurly: os << "OpenCurly"; break;
            case Symbol::CloseCurly: os << "CloseCurly"; break;
            case Symbol::OpenAngle: os << "OpenAngle"; break;
            case Symbol::CloseAngle: os << "CloseAngle"; break;
            case Symbol::Tilde: os << "Tilde"; break;
            case Symbol::Plus: os << "Plus"; break;
            case Symbol::Minus: os << "Minus"; break;
            case Symbol::Equal: os << "Equal"; break;
            case Symbol::Colon: os << "Colon"; break;
            case Symbol::Underscore: os << "Underscore"; break;
            case Symbol::Dot: os << "Dot"; break;
            case Symbol::Comma: os << "Comma"; break;
            case Symbol::Semicolon: os << "Semicolon"; break;
            case Symbol::SingleQuote: os << "SingleQuote"; break;
            case Symbol::DoubleQuote: os << "DoubleQuote"; break;
            case Symbol::Backtick: os << "Backtick"; break;
            case Symbol::Slash: os << "Slash"; break;
            case Symbol::BackSlash: os << "BackSlash"; break;
            case Symbol::Newline: os << "Newline"; break;
            case Symbol::CarriageReturn: os << "CarriageReturn"; break;
        }
        return os;
    }

    std::ostream &operator<<(std::ostream &os, const Token &token)
    {
        os << token.symbol;
        switch (token.symbol)
        {
            case amp::Symbol::Newline:
                break;
            default:
                os << ": '" << std::string_view{token.begin, token.size} << "'";
                break;
        }
        return os;
    }

} // namespace amp
