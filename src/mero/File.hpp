#ifndef HEADER_mero_File_hpp_ALREADY_INCLUDED
#define HEADER_mero_File_hpp_ALREADY_INCLUDED

#include <mero/Language.hpp>
#include <mero/Node.hpp>

#include <filesystem>
#include <optional>
#include <ostream>
#include <string>

namespace mero {

    class File : public Node
    {
    public:
        void init(Language language, const std::string_view &content);

        std::optional<Language> language() const;

        Node &root() { return *(Node *)this; }
        const Node &root() const { return *(const Node *)this; }

        void write(std::ostream &os) const;

    private:
        std::filesystem::path fp_;
        std::optional<Language> language_;
        std::string content_;
    };

} // namespace mero

#endif
