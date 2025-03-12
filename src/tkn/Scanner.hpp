#ifndef HEADER_apm_Scanner_hpp_ALREADY_INCLUDED
#define HEADER_apm_Scanner_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>
#include <tkn/Token.hpp>

#include <rubr/mss.hpp>

#include <string>

namespace tkn {

    Symbol parse_symbol(char ch);

    class Scanner
    {
    public:
        // Builder allows user to directly read data into content_
        template<typename Builder>
        ReturnCode init(Builder builder)
        {
            MSS_BEGIN(ReturnCode);
            MSS(builder(content_));
            MSS_END();
        }

        std::string_view content() const { return content_; }

        ReturnCode scan();

        const Tokens &tokens() const { return tokens_; }

    private:
        std::string content_;
        Tokens tokens_;
    };

} // namespace tkn

#endif
