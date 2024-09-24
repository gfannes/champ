## Split document in Lines
- Prefix: ` #-*$` and backtick
- Main
- Postfix: newline
- Output: Ranges

## Create hierarchy in Lines
- Stack of headers
- Stack of bullets

## Parse Line.main
- Take context from previous prefixes into account
	- Ad-hoc detection of code block of formula
- Tokenize
- Parse into Statements
	- Metadata
	- Link
	- String
	- Filter-out `&nbsp;`, ...

## Populate Node.attributes and Node.links from Line.stmts

