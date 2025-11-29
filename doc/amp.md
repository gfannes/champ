&&amp

# AMP DSL &&dsl

```
PATH: &&:PARENT:NAME&
      1??*******1111?
	  |||           +------- depends-on, optional
      ||+------------------- absolute, optional
      |+-------------------- definition, optional
      +--------------------- start-of-amp

PARENT: !~STRING
        ??111111
		|+------------------ template, optional
        +------------------- exclusive, optional

NAME: !~STRING*
      ??111111?
      ||      +------------- priority, optional
      |+-------------------- template, optional
      +--------------------- exclusive, optional
```
