# Ampersand Metadata Protocol
- Annotation Metadata Protocol

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

## Support specifying dependencies in 2 directions
- A Node that depends on another Tree
- A Tree that is used by another Node
	- How to express this Node? Or only allow Tree -> Tree dependencies in this case?

## Support nested projects
- &proj=amp
	- &proj=ch => same as `proj=/amp/ch`
	- &proj=/ch => same as `proj=/ch`

## &tdb Discriminate between AMP data and commented-out code
- Only allow AMP at the start of a comment for SourceCode?
- Check for parenthesis nesting? => cannot handle commented-out variable definitions

## Support AMP links
- `&[[title]]`
	- Still works as a link in Obsidian

## Document typical metadata usage
- `mef`: mental effort
	- [surge: unit of mef](https://jonisalminen.com/unit-of-cognitive-effort/)
