rank = computed recommendation
order = manual/display sequence

You can derive a recommended execution order from:

scope      # must before should before could
priority   # higher value first
dependencies # prerequisites first
effort     # smaller items may go earlier
risk       # risky/unknown items may go earlier

A simple model:

1. Respect dependencies first.
2. Prefer must-have over should-have over could-have.
3. Prefer higher priority.
4. Prefer higher risk earlier, to reduce uncertainty.
5. Prefer lower effort earlier when otherwise similar.

Example scoring:

scope: must=300, should=200, could=100, deferred=0
priority: highest=40, high=30, medium=20, low=10
risk: high=30, medium=20, low=10
effort: small=15, medium=10, large=5

Then:

rank_score = scope + priority + risk + effort_bonus

Dependencies are not just part of the score; they are constraints. A high-priority Story cannot be ordered before something it depends on.

So the algorithm is roughly:

Build dependency graph.
Topologically sort available items.
Within each available group, sort by rank_score.

I would still keep optional manual override:

rank_override: 10

or:

order: 10

Because humans sometimes know something the model does not:

stakeholder demo needs this first
developer availability
release train timing
external dependency
strategic optics

My naming recommendation:

scope: must | should | could | deferred
priority: highest | high | medium | low
effort: xs | s | m | l | xl
risk: low | medium | high
depends_on: [...]
order: 10              # optional manual override/display order

Then internally compute:

recommended_order

or:

rank

That gives you both:

default smart ordering
manual control when needed
clear metadata semantics
