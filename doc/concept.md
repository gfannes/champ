&& concept

# Grove
- A named filesystem folder that is will become part of the Tree
- Supports filtering on file extension and size
# Tree
- A tree of Nodes that correspond to files and filecontent parts
- Uses rubr.tree.Tree
# Node
- Keeps information on grove, folder, file and text
	- See mero.dto.Node.type
- Contains references into the DefMgr to
	- A define at this location
	- Many links to other Defs
		- Org: the reference is present in the content
		- Agg: the reference is inherited
# Forest
- Manages the Tree, Defines and Chores
# Define
- The definition of an amp annotation
	- Can be absolute or relative
	- Can occur only once
# Chore
- A Tree Node that contains amp.Path info
# Amp
## Path
- A full amp tag
	- Definition
	- Absolute
	- Dependency
	- Each part
		- Exclusive
		- Template: status, date, prio, wbs

