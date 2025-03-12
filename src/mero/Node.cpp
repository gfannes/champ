#include <mero/Node.hpp>

namespace mero {

    void Node::init()
    {
        childs_.resize(0);
    }

    Node &Node::emplace_child()
    {
        return childs_.emplace_back();
    }

    void Node::push_token(const tkn::Token &token)
    {
        tokens_.push_back(token);
    }

    void Node::write(std::ostream &os, const std::string_view &content) const
    {
        for (const auto &token : tokens_)
        {
            os << token.range.sv(content);
        }
    }

} // namespace mero
