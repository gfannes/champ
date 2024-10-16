# Command-line interface

## Distribute MD &todo &d0
- Distribute data within each Tree in MT
- Compute per Tree the reachable and incoming Trees
- Merge MD until convergence

## Make config persistent &todo &c0
- `ch`: list current config
- `ch -f abc`: select forest `abc`
- `ch se test`: search for test in forest `abc`
- `ch clear`: clear persistence
- Support using `ch` without persistence for in scripts and MT
- Store config in `.config/champ`
- Rename `.config/champ/config.toml` into `forests.toml`
- Could support push/pop to create a list of configs
