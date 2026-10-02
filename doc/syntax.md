&&syntax

# Definition
## Absolute
- `&&:a`
- `&&:a:b:c`
## Relative
- `&&b`
- `&&b:c`
## Synonym
- `&&:a &&synonym`
	- First definition will be used for relative path building

# Dependencies
- Resolving these references support partial matches
	- `&a:b` matches with `&&a:v1:b`
## Is part of
- `TaskA is part of &b`
## Is used by
- `TaskA is used by &b&`
