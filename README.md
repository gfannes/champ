# Champ

Command-line Hero for the Ampersand Metadata Protocol (AMP)

This crate contains a command-line utility to work with AMP data. It can:
- Search folders for AMP data
- Filter on specific paths
- Show unresolved AMP data

In the near future, we plan to:
- Support working with priorities, dates and durations
- Support LSP

## Syntax

An AMP metadata item is essentially a _path_, a sequence of _parts_. This sequence starts with a `&` and ends at the first space, newline or end-of-file. In the future, support for parts with

## explain How to use IvyLee &doc &todo

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
