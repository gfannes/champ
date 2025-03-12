#ifndef HEADER_mero_Parser_hpp_ALREADY_INCLUDED
#define HEADER_mero_Parser_hpp_ALREADY_INCLUDED

#include <ReturnCode.hpp>
#include <mero/File.hpp>
#include <tkn/Scanner.hpp>

namespace mero {

    class Parser
    {
    public:
        void init(const tkn::Scanner &scanner, Language language);

        ReturnCode parse(File &file) const;

    private:
        const tkn::Scanner *scanner_{};
        std::optional<Language> language_;
    };

} // namespace mero

#endif
