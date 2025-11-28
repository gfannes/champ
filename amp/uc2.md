&&uc2

Support planning items on a timeline and finding the next item to work-on.

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
- [*] Add date to File node
	- Probably as an Amp, but the systems seems not prepared for new amps

## Support working with start date and prio
- [x] Create new verb `pl/plan`
- [x] Distribute start date from root to leaf, can be overruled by org
- [x] Retain chores with a start date before now
- [*] Print chore content
	- Currently, only the amp.Paths are accessible, apparently
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

## Support working with durations
- Design DSL for duration: `1m2w3d4h`
- These aggregate leaf to root as sum

## Create overview in temporary text file
- [[File UI]], similar to [Magit](https://magit.vc/)

## List prio items without start date
- Eg from `champ check` verb, together with other analysis tools
