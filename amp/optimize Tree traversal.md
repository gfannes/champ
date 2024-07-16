# Plan
- Keep `ignore::gitignore::Gitignore` and `ignore::gitignore::GitignoreBuilder` for folders that have a `.gitignore` file
	- Use `BTreeMap` to store info based on Path parts
- Create/reuse a gitignore depending on the presence of an actual gitignore file
