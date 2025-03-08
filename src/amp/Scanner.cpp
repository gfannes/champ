#include <amp/Scanner.hpp>

#include <rubr/mss.hpp>

#include <array>

namespace amp {

    ReturnCode Scanner::operator()(std::string_view sv)
    {
        MSS_BEGIN(ReturnCode);
        MSS_END();
    }

    Kind parse_symbol(char ch)
    {
        static std::array<Kind, 256> s_ch__kind;
        static bool s_do_init = true;
        if (s_do_init)
        {
            s_do_init = false;
            for (auto &kind : s_ch__kind)
                kind = Kind::None;
            s_ch__kind[' '] = Kind::Space;
            s_ch__kind['!'] = Kind::Exclamation;
            s_ch__kind['?'] = Kind::Questionmark;
            s_ch__kind['|'] = Kind::Pipe;
            s_ch__kind['@'] = Kind::At;
            s_ch__kind['#'] = Kind::Hashtag;
            s_ch__kind['$'] = Kind::Dollar;
            s_ch__kind['%'] = Kind::Percent;
            s_ch__kind['^'] = Kind::Hat;
            s_ch__kind['&'] = Kind::Ampersand;
            s_ch__kind['*'] = Kind::Star;
            s_ch__kind['('] = Kind::OpenParens;
            s_ch__kind[')'] = Kind::CloseParens;
            s_ch__kind['['] = Kind::OpenSquare;
            s_ch__kind[']'] = Kind::CloseSquare;
            s_ch__kind['{'] = Kind::OpenCurly;
            s_ch__kind['}'] = Kind::CloseCurly;
            s_ch__kind['<'] = Kind::OpenAngle;
            s_ch__kind['>'] = Kind::CloseAngle;
            s_ch__kind['~'] = Kind::Tilde;
            s_ch__kind['+'] = Kind::Plus;
            s_ch__kind['-'] = Kind::Minus;
            s_ch__kind['='] = Kind::Equal;
            s_ch__kind[':'] = Kind::Colon;
            s_ch__kind['_'] = Kind::Underscore;
            s_ch__kind['.'] = Kind::Dot;
            s_ch__kind[','] = Kind::Comma;
            s_ch__kind[';'] = Kind::Semicolon;
            s_ch__kind['\''] = Kind::SingleQuote;
            s_ch__kind['"'] = Kind::DoubleQuote;
            s_ch__kind['`'] = Kind::Backtick;
            s_ch__kind['/'] = Kind::Slash;
            s_ch__kind['\\'] = Kind::BackSlash;
            s_ch__kind['\n'] = Kind::Newline;
            s_ch__kind['\r'] = Kind::CarriageReturn;
        }
        return s_ch__kind[ch];
    }

} // namespace amp
