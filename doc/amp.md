&&amp

# AMP &&dsl

- Alias: extra name for a definition. All non-first definitions in an amp.Node are aliasses for that Node.

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
