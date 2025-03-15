#include <mero/Parser.hpp>

#include <rubr/ix/Range.hpp>
#include <rubr/macro/capture.hpp>

namespace mero {

    void Parser::init(const tkn::Scanner &scanner, Language language)
    {
        scanner_ = &scanner;
        language_ = language;
    }

    ReturnCode Parser::parse(File &file) const
    {
        MSS_BEGIN(ReturnCode, "");

        MSS(!!scanner_);
        const auto &scanner = *scanner_;

        MSS(!!language_);
        file.init(*language_, scanner.content());
        file.root().init();

        Node *line = &file.root().emplace_child();

        for (const auto &token : scanner.tokens())
        {
            L(C(token));
            switch (token.symbol)
            {
                case tkn::Symbol::Newline:
                    for (auto _ : rubr::ix::make_range(token.range.size))
                        line = &file.root().emplace_child();
                    break;
                case tkn::Symbol::CarriageReturn:
                    break;
                default:
                    line->push_token(token);
                    break;
            }
        }

        MSS_END();
    }

} // namespace mero
