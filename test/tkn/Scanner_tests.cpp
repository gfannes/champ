#include <tkn/Scanner.hpp>

#include <catch2/catch_test_macros.hpp>

TEST_CASE("parse_symbol", "[ut][amp][Scanner]")
{
    REQUIRE(tkn::parse_symbol('a') == tkn::Symbol::Word);
    REQUIRE(tkn::parse_symbol('?') == tkn::Symbol::Questionmark);
}
