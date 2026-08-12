# README_SHORT

MATLAB R2024a+.

Quick start:
1. Run install script, or download repo to `C:\Users\<you>\Desktop\sm-dev` (or `sm-main` if on main branch).
2. Copy example main script `demos/demo.m` to outside this repo. Edit:
- instrument addresses
- `_Use` flags
- `requireSetCheck` flags (`false` = no settle wait)
- repository-root `secrets.env` with `slack_notification_api_token`; see **Slack API Setup** in `README.md`
- `recipe.slack_notification_account_email` for private queue notifications (a channel ID is needed only when this is empty)
- channels and instrument settings as needed
- use `instrument_K2450` for Keithley 2450 instruments; do not run a 2450 in 2400 emulation mode
3. Run.

Key concepts:
- Vector channels are faster than separate scalar reads: `XTheta` is faster than `X` + `Theta`. Saved/plotted as scalars: `XTheta_1` = `X`, `XTheta_2` = `Theta`.
- The measurement engine runs in a separate process.
- Scan GUI `Run` = safe mode. Point-by-point updates. Slower, safer. Use for gate-range tests.
- Queue GUI `Run` = turbo mode. Asynchronous, fast.
- "When finished or canceled" is Set After: checked rows set channels, then unchecked rows record final values before the final save.
- Protected `V_bg`/`V_tg` channels can immediately zero a gate and gracefully stop after 3 out-of-limit current reads at strictly increasing absolute SET voltage (configurable, minimum 2); use the protected current/VI channels, not `_raw`, for this check.
- Press `Escape` or confirm closing the plot window to stop gracefully. Finish actions and final saving still run, and queued entries that have not started remain pending.
- Numeric range edits in the scan GUI preserve textbox focus; repeated Run clicks during an active scan are ignored.
- The programmatic queue-GUI redesign is documented in `docs/QUEUE_GUI_DESIGN.md` but is not implemented yet.
- Save and load scan definitions to reuse common scans and avoid rebuilding them each session.
