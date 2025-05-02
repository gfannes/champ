&!:uc1

# Create project breakdown &!breakdown
- Must support defining a tree of subtasks as AMP tags
	- [x] Join relative defs into absolute defs
		- [x] Use rubr.tree.Tree to store Nodes
		- [x] Add parent backlinks
		- [x] Represent Folders, Files and Nodes in a tree
		- [x] Join Folders and Files
- Describe these subtasks in Markdown
- List project breakdown from CLI
	- [ ] Filter-out tags that do not match
	- [x] Sort by fuzzy match score
	- [ ] Support selecting defs
	- [ ] Could document the DSL for searching

# Search for AMP definitions &!define
- Must support [[Helix]] via [[Language Server Protocol (LSP)]]
	- Use workspace symbols
- [ ] Search in amp.Path, not in terms
- [ ] Reload when file is changed/created
- [ ] Reload from time to time
- [ ] Must support specification of defaults in `~/.config/champ/default.zon`
	- [ ] Reload when changed, check from time to time

# Annotate parts of source code with project and status tags &!annotate
- Could replace `org` with `champ`
	- Improved Markdown parsing, consistent with `champ`
- [ ] Support aggregation of AMP tags
- [ ] Support specification of AMP tags for a folder
	- Use `_tree.md`
		- Only aggregate AMP tags specified at the top
	- Rename existing `_.amp` and update Rust code

# Find all references &!search
- [ ] Resolve AMP tags against defs
	- [ ] Report unresolved AMP tags in CLI
- [ ] Must filter done items by default
- [ ] Could support searching all references
- [ ] Must only report nodes with an AMP tag
- [ ] Must support identifying next subtasks to work on

