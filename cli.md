# Command-line interface

## Support filter with Query &task
- Use amp.Tree to parse args
- First is needle, rest are filters

## Support flexible CLI &task
- Support mix of options and words
	- Might require to drop `clap`

## Distribute MD &task
- Distribute data within each Tree in MT
- Compute per Tree the reachable and incoming Trees
- Merge MD until convergence

## Support detailed view &task
- Collect results in some struct
- Detailed view must show subtree

## Make config persistent &task
- `ch`: list current config
- `ch -f abc`: select forest `abc`
- `ch se test`: search for test in forest `abc`
- `ch clear`: clear persistence
- Support using `ch` without persistence for in scripts and MT
- Store config in `.config/champ`
- Rename `.config/champ/config.toml` into `forests.toml`
- Could support push/pop to create a list of configs

## Support for default forest selection &task
- Store in `.config/champ/active.toml`

## Show 6 prios &tbd

## Show next item &tbd
