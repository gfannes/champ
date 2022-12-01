#include <util/log.hpp>

#include <gubg/Logger.hpp>

namespace util { namespace log {

    gubg::Logger s_logger;

    void set_level(int level)
    {
        s_logger.level = level;
    }
    std::ostream &os(int level)
    {
        return s_logger.os(level);
    }
    std::ostream &error()
    {
        return s_logger.error();
    }
    std::ostream &warning()
    {
        return s_logger.warning();
    }

}} // namespace util::log