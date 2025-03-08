# Chimp, the zig implementation of champ

## &todo Take groves into account
- Parse from toml or naft

## Measure tree iteration and compare with champ

# Comparison between C++, Zig and Runst

- Lifetime and ownership is not clear in Zig
- Filesystem iteration is faster in Zig vs C++: 127ms vs 158ms for iterate root-all, taking .gitignore into account
	- Memory allocations inside std::filesystem::path are probably the root cause
- Errors are nice in Zig, in C++ it is difficult to merge ReturnCodes
- Memory leaks are easy in Zig
- Passing and storing std.mem.Allocator is annoying
- Optionals are nice in Zig
- UTF8 is often too strict in Rust
- Lambdas in Rust do not work well due to ownership
- Lambdas are non-existing in Zig, leading to more verbose source code
- Symbol shadowing rules in Zig are too strict, resulting in artificial name variants
- Cargo is a big plus for Rust
- Zig is clean and nice
- It is not possible to cancel a defer operation, making it difficult to have safe code that hands-over items to something else
