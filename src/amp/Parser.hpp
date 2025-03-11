#ifndef HEADER_amp_Parser_hpp_ALREADY_INCLUDED
#define HEADER_amp_Parser_hpp_ALREADY_INCLUDED

#include <amp/Scanner.hpp>
#include <ReturnCode.hpp>

namespace amp {

    class Parser
    {
    public:
        void init(const Scanner &scanner);

        ReturnCode parse() const;

    private:
        const Scanner *scanner_{};
    };

} // namespace amp

#endif
