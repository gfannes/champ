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

## Support working with start date and prio
- Create new verb `pl/plan`
- Distribute start date from root to leaf, can be overruled by org
- Retain chores with a start date before now
- Sort search results by prio
- Support searching in 'org' and 'agg'
	- First search part searches in 'org', others search in 'agg'?
- Design DSL for date:
	- `20250210`
	- `202502` => `20250201`
	- `2025` => `20250101`
	- `q3` => closest `XXXX0701`
	- `w23` => closest year-week
- Convert all dates internally to YYYYMMDD

## Support working with durations
- Design DSL for duration: `1m2w3d4h`
- These aggregate leaf to root as sum
