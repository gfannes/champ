#include <amp/Parser.hpp>

#include <rubr/macro/capture.hpp>

namespace amp {

    void Parser::init(const Scanner &scanner)
    {
        scanner_ = &scanner;
    }

    ReturnCode Parser::parse() const
    {
        MSS_BEGIN(ReturnCode, "");
        MSS(!!scanner_);
        const auto &scanner = *scanner_;

        for (const auto &token : scanner.tokens())
        {
            L(C(token));
        }

        MSS_END();
    }

} // namespace amp
