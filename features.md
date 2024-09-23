## Show 6 prios

## Show next item

## Create overview of PM best practices
- [Ivy-Lee](https://tweek.so/calendar/ivy-lee-method)
- Getting things done
	- Indicated 'next' item that can be processed

## Support pesistent project enumeration
- Config file

## Define DSL for metadata

## Show file/folder metadata
- Modification time
- Git status
- Size

## Show links and backlinks in bottom-left

## Show statistics in bottom rows

## Display metadata async
- Retrieving git status should not affect scrolling speed

## Support copy/paste

## Show help

## Show all `next` items found
- Filter on `proj`

## Support opening found items in editor

## Support cut/paste on tree.Forest
- Support write-out as well

## Check for filesystem updates from time to time

## Consider using [ratatui](https://ratatui.rs/) for TUI
- Block, Calendar, List, Table, Tabs

## Support specifying dependencies in 2 directions
- A Node that depends on another Tree
- A Tree that is used by another Node
	- How to express this Node? Or only allow Tree -> Tree dependencies in this case?

## Support nested projects
- &proj=amp
	- &proj=ch => same as `proj=/amp/ch`
	- &proj=/ch => same as `proj=/ch`

## Replace `util:Result` with `anyhow::Result`
- For backtrace support when errors occur

## Parse tree.Tree MT

## Support for default forest selection
- Store in `.config/champ/active.toml`

## Rename tree into forest for ch

## Create naft CLI to work with folders in a single file

## &tdb Discriminate between AMP data and commented-out code
- Only allow AMP at the start of a comment for SourceCode?
- Check for parenthesis nesting? => cannot handle commented-out variable definitions

## Rework/merge amp.Forest and tree.Forest
- amp.Forest is more like enumeration
- tree.Forest represents the forest
- maybe speed-up enumeration when Forest is bounded with direct use of gitignore

## Create website
- http://champ.net
- http://amp-lang.org

## Define AMP protocol and per-file injection
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

## Make config persistent
- `ch`: list current config
- `ch -f abc`: select forest `abc`
- `ch se test`: search for test in forest `abc`
- `ch clear`: clear persistence
- Support using `ch` without persistence for in scripts and MT
- Store config in `.config/champ`
- Rename `.config/champ/config.toml` into `forests.toml`
- Could support push/pop to create a list of configs

## Support excluding files by pattern
- Filter-out false positives

## Fully parse Markdown
- Do not match AMP in code blocks
