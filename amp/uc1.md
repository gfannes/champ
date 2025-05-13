&!:uc1

# Create project breakdown &!breakdown
- Must support defining a tree of subtasks as AMP tags
	- [x] Join relative defs into absolute defs
		- [x] Use rubr.tree.Tree to store Nodes
		- [x] Add parent backlinks
		- [x] Represent Folders, Files and Nodes in a tree
		- [x] Join Folders and Files
		- [x] Add AMPs from first line to File
- Describe these subtasks in Markdown
- List project breakdown from CLI
	- [ ] Filter-out tags that do not match
		- Update rubr.fuzz
	- [x] Sort by fuzzy match score
- [ ] Add 'fix' mode to champ
	- [ ] Warn on amps without definition

# Search for AMP defs and tags from editor &!define
- [x] Must support [[Helix]] via [[Language Server Protocol (LSP)]]
	- [x] Use workspace symbols
- [x] Search in amp.Path, not in terms
	- [x] Create seperate AMPs
	- [x] Resolve AMP tags against defs
		- Node.orgs must always be resolved
		- [x] First might be def
		- [x] Remove Node.def
		- [x] Resolve amps into Node.orgs
			- [x] Create flat list of defs as part of joinDefs()
			- [x] Report doubles via log
				- [x] Impl 'amp.Path.is_fit()'
			- [x] Dfs over tree
				- [x] Parse each amp
				- [x] Resolve non-defs and append
				- [x] Report relative amps that cannot be resolved
				- [x] Report ambiguous fits
	- [x] Make LSP search in Node.orgs
		- [x] Document symbols
			- [x] Create string repr
		- [x] Workspace symbols
- [x] Search smart-case
	- Impl in rubr.fuzz based on casing of needle
- [x] Reload when file is changed/created
- Support searching for next Chore to execute
	- [x] Interpret '[?]' as AMP
		- Discriminate between Markdown and Wiki links
	- [ ] Create DSL for 'todo', 'wip' and 'next'
- [x] Support searching for unresolved AMPs
	- [x] Add catch-all AMP UNRESOLVED
	- [ ] Make this configurable
- [ ] Reload from time to time
- [x] Must support specification of defaults in '~/.config/champ/config.zon#default'
	- [ ] Reload when changed, check from time to time

# Annotate parts of source code with project and status tags &!annotate
- [ ] Support aggregation of AMP tags
	- [ ] Tag distribution from root to leaf
		- Def is also an org and should be used in aggregation etc
			- Only for tags, not for templates or numbers etc.
	- [ ] Trailing ! indicates current Chore _uses_ AMP
		- Default behavior is that current Chore _is part of_ AMP
		- Is this the same as a reverse tag?
	- [ ] Support Markdown and Wiki links to other files
		- [?] Do we need some marker to take them into account
- [ ] Support specification of AMP tags for a folder
	- Use '_tree.md'
		- Only aggregate AMP tags specified at the top
	- Rename existing '_.amp' and update Rust code

# Find all references &!search
- [x] Collect content range per Node
- [/] Convert Nodes with AMP info into Chores
	- [x] Merge Defs into chore.Chores
	- [*] Make app.Lsp symbols work with this
		- [x] Add nodes during setup of Forest
- [*] Support 'goto definition'
- [*] Support 'find references'
- [ ] Must filter done items by default
	- [ ] Could support searching all references
- [x] Must only report nodes with an AMP tag
- [x] Must support identifying next subtasks to work on
