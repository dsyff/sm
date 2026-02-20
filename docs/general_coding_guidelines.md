# Coding Guidelines

- Keep implementations **concise**—avoid redundant fallbacks, superfluous assertions, or blunt `warning` spam. If unsure about instrument behavior, pick one option and throw a clear error if expectations are not met. This narrows down the exact behavior needed in a final version.
- Do not add helper methods unless they will be reused and reduce overall line count.
- The main measurement loop (now in `measurementEngine`) must be fast. Pre-emptively do any computation or initialization that can be done before the loop.
- Avoid fixed pacing pauses in rack/engine hot paths; prefer per-instrument pacing via `instrumentInterface.writeCommandInterval`.
- In MATLAB, always prefer double quotes and strings unless a function explicitly requires char arrays.
- Prefer `Name = value` format over `"Name", value` pairs.
- Remember to set `_Use` flags to 0 in the main demo `demo.m` before staging new changes.
- Remember to set email address to "" in all demo files before staging changes for security.
- Prefer datetime/duration classes over `now`/datenum/tic/toc.
- For terminal/status output in worker-capable code (especially `code/sm2` and instrument code), use `experimentContext.print(...)` instead of direct `fprintf(...)`/`disp(...)`. `experimentContext.print` handles local vs worker routing and preserves worker message forwarding to client via DataQueue.
