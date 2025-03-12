#ifndef HEADER_mero_Node_hpp_ALREADY_INCLUDED
#define HEADER_mero_Node_hpp_ALREADY_INCLUDED

#include <amp/Metadata.hpp>
#include <tkn/Token.hpp>

#include <ostream>
#include <vector>

namespace mero {

    class Node;
    using Childs = std::vector<Node>;

    class Node
    {
    public:
        void init();

        const Childs &childs() const { return childs_; }
        const tkn::Tokens &tokens() const { return tokens_; }

        Node &emplace_child();

        void push_token(const tkn::Token &token);

        void write(std::ostream &os, const std::string_view &content) const;

    protected:
        tkn::Tokens tokens_;
        Childs childs_;
    };

} // namespace mero

#endif
