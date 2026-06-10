# User Rules

## 1) Implementation style
- Keep implementations concise.
- Fallbacks are not allowed unless explicitly requested or documented as a required legacy compatibility path.
- Avoid redundant fallbacks, superfluous assertions, and warning spam.
- If instrument behavior is uncertain, pick one behavior and throw a clear error when expectations are not met.
- Do not add helper methods unless they are reused and reduce overall line count.

## 2) Required context loading
- Before starting work in a repository, search for README files and read them.
- Read additional documentation referenced by README files when relevant to the task.

## 3) Email scrub before stage/push for public repos
- Before staging, committing, or pushing, run the sensitive-email scrub required by the current session instructions.
- Remove or redact any occurrences before `git add`, `git commit`, or `git push`.

## 4) Agent-generated artifacts
- Store agent-generated images/screenshots for the user in `temp/` inside the workspace (git-ignored), not the OS temp folder, so links survive temp cleanup.
