#include <amp/Scanner.hpp>

#include <catch2/catch_test_macros.hpp>

TEST_CASE("parse_symbol", "[ut][amp][Scanner]")
{
    REQUIRE(amp::parse_symbol('a') == amp::Symbol::Word);
    REQUIRE(amp::parse_symbol('?') == amp::Symbol::Questionmark);
}
