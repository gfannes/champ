#ifndef HEADER_str_Range_hpp_ALREADY_INCLUDED
#define HEADER_str_Range_hpp_ALREADY_INCLUDED

#include <cstdint>
#include <string_view>

namespace str {

    struct Range
    {
        std::uint32_t ix{};
        std::uint32_t size{};

        std::string_view sv(const std::string_view &sv) const { return sv.substr(ix, size); }
    };

} // namespace str

#endif
