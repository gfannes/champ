# Sorting Chores works as follows &&chore:sort:
- Remove Chores with dates into the future
- Use order information when present
- When the order is the same
	- Tasks without a date come first, preventing these to become invisible. No date means: without explicit scheduling but available now.
	- Older tasks come before newer tasks, preventing these to sink beneath newer work.

