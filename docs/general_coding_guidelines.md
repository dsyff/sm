## 🧭 Coding Guidelines
- Keep implementations **concise**—avoid redundant fallbacks, superfluous assertions, or blunt `warning` spam. If unsure about instrument behavior, pick one option and throw a clear error if expectations are not met. This narrows down the exact behavior needed in a final version.
- Do not add helper methods unless they will be reused and reduce overall line count.
- The main loop inside `smrun_new.m` must be fast. Pre-emptively do any computation or initialization that can be done before the loop.
- In MATLAB, always prefer double quotes and strings unless a function explicitly requires char arrays.
- Prefer `Name = value` format over `"Name", value` pairs.