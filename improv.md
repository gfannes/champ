# Improvements

## Replace `util:Result` with `anyhow::Result`
- For backtrace support when errors occur

## Parse tree.Tree MT

## Rework/merge amp.Forest and tree.Forest
- amp.Forest is more like enumeration
- tree.Forest represents the forest
- maybe speed-up enumeration when Forest is bounded with direct use of gitignore

## Fully parse Markdown &todo &b0
-  Support links: `&[[parse Markdown into tree.Tree]]`
- Do not match AMP in code blocks, latex formulas, quoted things or links
