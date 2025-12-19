# Ampersand Metadata Protocol (AMP) &&:amp

## DONE Interpret AMP on first Node as AMP for Tree
- All metadata placed on the first line of a file (a markdown paragraph) applies to the complete file
- All metadata placed in `_amp.md` applies to the folder, recursively

## DONE Set ~date from filename
- For `daily/YYYY-MM-DD.md` format

## Specification &&spec
- AMP data is searched in _metadata_, not in actual data
	- For source code, the metadata are _the comments_
	- For Markdown, the metadata is _the text, excluding code blocks and formulas_
- AMP data consists of Paths, sequences of Parts
	- The `&` character starts an AMP Path. To avoid false positive detection, the `&` should occur at the start of a metadata section or occur after a space/tab character.
	- If the next character is a `!`, it is a _definition Path_. Definition Paths are used to resolve other Paths. They allow:
		- Using shorter Paths when there is no ambiguity: `&todo` can be used iso `&status:todo` if there is no other definition Path that matches with `todo` expect `&&:status:todo`
		- Specify typed data via the use of templates
	- The `:` character is the Path separator
		- A Path starting with a `:` is an absolute Path
		- Note: `:` is preferred over `/` because most Paths will have size 2 and read like a named parameter specification: `&status:done`.
	- When escaping is necessary, the item can be wrapped as
		- `::(((item)))` if `item` does not start with a `(`, using as many `(((` as necessary to ensure there is no match of `)))` in `item`
		- `::{{{item}}}` if `item` does not start with a `{`, using as many `{{{` as necessary to ensure there is no match of `}}}` in `item`
		- Note that we do not allow empty items in Path, avoiding a conflict with `::` and allowing one to trim trailing `:` as is `&todo: Finish this`
	- Template Path Parts for defs start with `~`
		- Eg: the `&&:eta:~date` definition allows you to specify ETA metadata as `&eta:2024-11-06`
		- Note: `$` cannot be used as it conflicts with Markdown formula
- A trailing `!` indicates _exclusivity_. This is typically used for status information: something is either _todo_ or _done_, but not both.
- [?] Maybe reverse a path to improve free search?
	- `&todo` matches with both `&todo` and `&todo:status`
	- How can we represent an absolute path? #todo/status/!
	- Less intuitive

## Support pesistent project enumeration
- Config file
- Support excluding files by pattern
	- Filter-out false positives

## Define AMP protocol and per-file injection
- Define DSL for metadata
- Below rules have no false positive on SourceCode in root-all
- Prefer `&` over `@`
	- Reduce false-positives on doxygen and javadoc
	- Reduce false-positives on commented Ruby code with instance variables
- Skip HTML entities like `&nbsp;`
- Only allow AMP at the start of a comment for SourceCode
	- Also support nested comments: eg, when AMP data after a line of code gets commented-out itself
		- `// f(&i); // @tag` => `&tag` should be detected, but `&i` should not
- Only allow `&` if there is a none-`&` following
- Check that AMP does not end with `,` or `)` to filter-out function calls with address parameters, each on a separate line
```
	// f(
	//	&i,
	//	&j);
```

## Define metadata aggregation
- Original _relative_ AMP metadata definition
- Root-to-leaf pass to transform relative MD into _absolute_
	- Path, link targets
- Root-to-leaf pass to distribute MD
	- Only non-aggregate MD
- Leaf-to-root pass to aggregate MD
	- Sum numerical values, duration
	- Min deadlines
	- Collect non-aggregate MD from `Map<String, String>` into `Map<String, Set<String>>`

## Support specifying dependencies in 2 directions
- A Node that depends on another Tree
- A Tree that is used by another Node
	- How to express this Node? Or only allow Tree -> Tree dependencies in this case?

## DONE Support nested projects
- Support proj statement that does not append to the current proj path, but resolves into an existing one
	- Use of absolute and relative definitions
	- `&:abs` and `&rel`

## DONE Support colored output
- Depending on prio

## Discriminate between AMP data and commented-out code
- Only allow AMP at the start of a comment for SourceCode

## Support AMP links
- `&[[title]]`
	- Still works as a link in Obsidian

## Document typical metadata usage
- `mef`: mental effort
	- [surge: unit of mef](https://jonisalminen.com/unit-of-cognitive-effort/)

## Identify all Markdown headers as tasks?
