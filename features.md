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
