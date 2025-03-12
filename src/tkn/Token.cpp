#include <tkn/Token.hpp>

namespace tkn {

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
        os << token.symbol << ' ' << token.range.ix << ' ' << token.range.size;
        return os;
    }

} // namespace tkn
