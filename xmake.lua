-- Load includes first since they might override our settings
includes("ext/rubr")

set_languages("c++23")
add_rules("mode.release") -- Enable with `xmake f -m release`
add_rules("mode.debug")   -- Enable with `xmake f -m debug`
add_requires("catch2")

-- -- Ensure debugging symbols exist even in release mode
-- if is_mode("release") then
--     set_symbols("debug")  -- Keeps debug info
--     set_optimize("fast")  -- Keeps optimizations (-O2)
--     add_cxflags("-fno-omit-frame-pointer", {force = true})  -- Required for perf
--     add_ldflags("-fno-omit-frame-pointer", {force = true})  -- Required for perf
-- end

target("amplib")
    set_kind("static")
    add_files("src/cli/**.cpp")
    add_files("src/amp/**.cpp")
    add_files("src/tkn/**.cpp")
    add_files("src/mero/**.cpp")
    remove_files("src/cli/main.cpp")
    add_includedirs("src", {public=true})
    add_deps("rubr")

target("amplib_ut")
    set_kind("binary")
    add_files("test/**.cpp")
    add_deps("rubr", "amplib")
    add_packages("catch2")

target("ampp")
    set_kind("binary")
    add_files("src/cli/main.cpp")
    add_deps("amplib")
