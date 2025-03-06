set_languages("c++20")
add_rules("mode.release") -- Enable with `xmake f -m release`
add_rules("mode.debug")   -- Enable with `xmake f -m debug`
add_requires("catch2")

-- &shortcut: Load ext/rubr/xmake.lua instead
target("rubr")
    set_kind("static")
    add_files("ext/rubr/src/**.cpp")
    add_includedirs("ext/rubr/src", {public=true})

target("ampp")
    set_kind("binary")
    add_files("src/cli/**.cpp")
    add_includedirs("src")
    add_deps("rubr")

-- target("unit_tests")
--     set_kind("binary")
--     add_files("test/**.cpp")
--     add_deps("rubr")
--     add_packages("catch2")
