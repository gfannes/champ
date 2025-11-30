&&uc2 &s:202511

Support planning items on a timeline and finding the next item to work-on.

- [x] Support setting `&s:` on first line in this file
- [x] When aggregating amps, retain max one amp per def to take the `org ~status/~date` over the parent &p:a
	- Allows pushing tasks into the future when the start date comes from the filename (and is thus difficult to update)
- [ ] Cleanup current false-positive todos
- [*] Inherit dependencies from defs to inject their metadata into this local extension
	- When linking to a def, take the `minimal ~date`, `top ~prio` and `local ~status` between parent and that def
- [x] Add support for `~prio` to fine-tune the order of the task list &p:a
	- [x] Move datex into amp folder as well to handle all templated metadata in the same namespace
- [x] Improve display of chores for search and plan
	- [x] Collect all chores, sort, segment per different path and print these segments in reverse order
		- [x] Support using normal order with `-r`
	- [x] Sort according to prio/match depending on the task
- [ ] Add CLI option `-s` for today, `-S` date for specific date
	- [ ] Use _end of period_ iso begin (eg 2025q1 should be 20250331 iso 20250101)
- [ ] Add CLI option `-t` for text search into `n.content`
- [x] Add CLI option `-d` for details to display amp metadata as well
- [ ] Push local amps to def when this is a dependency to support scheduling defs from the agenda
- [ ] Merge search and plan
	- Search uses fuzzy matching, plan uses prio and hard filter...
		- Maybe use some common layer but keep the different verbs

## Support use of prios
- Symbols that can be used to indicate a prio:
	- `*`: matches with _next_ from `[*]`
	- `!`: indicates importance
- Optional letter and optional digit
	- Default letter: `c`
	- Default digit: `4`
- Handle case-insensitive
- Prefix or postfix or both? `&!a` `&a!` `[a*]` `[*a0]` `&a*0`
- Document strategy:
	- start now (a), tomorrow (b), next week (c), next month (d), next quarter (e), next year (f)
	- optional digit is to swap order where necessary

## Automatically inject start date from logbook
- [x] Find date in filepath
- [x] Add date to File node
	- [x] Should an amp.Path.Part support non-string data?
	- [x] Rework to use ArenaAllocator to avoid memory handling
		- [x] aa is used for Node.path and Node.content
- [*] When multiple s.~date, take org

## Support working with start date and prio
- [x] Create new verb `pl/plan`
- [x] Distribute start date from root to leaf, can be overruled by org
- [x] Retain chores with a start date before now
- [x] Print chore content
	- Currently, only the amp.Paths are accessible, apparently
	- [x] Always setup Node.content, requires use of aa to manage memory
	- Maybe collect selected nodes in a new Tree and print that
		- Could also be used to extract subtrees for create a PR withouth amp annotations
- Sort search results by prio
- Support searching in 'org' and 'agg'
	- First search part searches in 'org', others search in 'agg'?
- [x] Design DSL for date:
	- `20250210`
	- `202502` => `20250201`
	- `2025` => `20250101`
	- `y25q3` => `20250701`
	- `y25w23`
- [x] Convert all dates internally to std.time.epoch.YearAndDay
- [*] Merge `search` and `plan`
- [*] Create LSP command for this
	- Goto def/goto decl could be used for todo items in local file and workspace
	- Diagnostics will probably not work in Helix due to only diagnostics for open files are retained

## Support working with durations
- Design DSL for duration: `1m2w3d4h`
- These aggregate leaf to root as sum

## Create overview in temporary text file
- [[File UI]], similar to [Magit](https://magit.vc/)

## List prio items without start date
- Eg from `champ check` verb, together with other analysis tools
