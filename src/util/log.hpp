#ifndef HEADER_util_log_hpp_ALREAD_INCLUDED
#define HEADER_util_log_hpp_ALREAD_INCLUDED

#include <ostream>

namespace util { namespace log {

    void set_level(int level);
    std::ostream &os(int level);
    std::ostream &error();
    std::ostream &warning();

}} // namespace util::log

#endif
