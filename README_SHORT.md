# README_SHORT

MATLAB R2024a+.

Quick start:
1. Run install script, or download repo to `C:\Users\<you>\Desktop\sm-dev` (or `sm-main` if on main branch).
2. Copy example main script `demos/demo.m` to outside this repo. Edit:
- instrument addresses
- `_Use` flags
- `requireSetCheck` flags (`false` = no settle wait)
- `recipe.slack_notification_account_email` for queue notifications
- channels and instrument settings as needed
3. Run.

Key concepts:
- Vector channels are faster than separate scalar reads: `XTheta` is faster than `X` + `Theta`. Saved/plotted as scalars: `XTheta_1` = `X`, `XTheta_2` = `Theta`.
- The measurement engine runs in a separate process.
- Scan GUI `Run` = safe mode. Point-by-point updates. Slower, safer. Use for gate-range tests.
- Queue GUI `Run` = turbo mode. Asynchronous, fast.
- Press `Escape` to stop. Instant only in safe mode.
