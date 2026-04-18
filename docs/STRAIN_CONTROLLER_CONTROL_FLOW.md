# Strain Controller Control Flow

This diagram is a simplified view of the strain controller in [instrument_strainController.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/instrument_strainController.m:15) and [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:240).

Simplifications used here:
- Treat the actuator as a single piezo voltage `V_piezo`.
- Ignore the real outer/inner split (`V_str_o`, `V_str_i`).
- Ignore the real "ramp to anchor point first" branch logic.
- Keep the real asynchronous command path, measurement path, bounds update, and error-to-voltage stepping behavior.

## Block Diagram

```mermaid
flowchart TD
    A[User / scan engine<br/>smset or rackSet on del_d, T, activeControl] --> B[instrument_strainController wrapper<br/>dogSet / dogGet / dogCheck]
    B --> C[strainWatchdog command handler]

    C --> D{Command type?}
    D -->|SET del_d| E[Update displacement target]
    D -->|SET T| F[Update temperature target<br/>write immediately if control is off]
    D -->|SET activeControl = 1| G[Validate calibration params and tare<br/>Seed target from current del_d]
    D -->|GET / CHECK| H[Return cached controlled values<br/>or direct hardware reads]

    G --> I
    E --> I
    F --> I

    I{activeControl on?}
    I -->|No| J[Idle loop<br/>only service commands]
    I -->|Yes| K[Apply new targets<br/>If T target changed: rackSetWrite T]

    K --> L[Acquire feedback<br/>rackGet CpQ, piezo V/I, T]
    L --> M[Compute state<br/>C = C_comp Cp,Q<br/>d = C2d C<br/>del_d = d - d_0]
    M --> N[Compute error<br/>e = del_d_target - del_d]
    N --> O[Check safety / termination flags<br/>stall or overload<br/>voltage-limit reached<br/>within del_d tolerance]
    O --> P[Update temperature-based voltage bounds<br/>V_min(T), V_max(T)]
    P --> Q[Choose next voltage move<br/>If e > 0 step V_piezo toward V_max<br/>If e < 0 step V_piezo toward V_min<br/>step size = min 0.5 V, |e| * gain]
    Q --> R[Clamp to allowed bounds]
    R --> S[rackSetWrite V_piezo]
    S --> T[Update atTarget flag<br/>true if tolerance reached, saturated, or overloaded]
    T --> U[Log sample to timetable]
    U --> I

    H --> I
    J --> I
```

## What This Means In Practice

- `smset("del_d", target)` does not directly talk to the piezo supply. It updates the watchdog target, and the watchdog loop decides the next voltage step.
- The controller is feedback-based, not open-loop: it reads `Cp` and `Q`, compensates them, converts to displacement, compares against `d_0`, and then updates the piezo voltage.
- Temperature is part of the control path because the allowed piezo voltage window is recomputed from `T`.
- The controller does not continuously solve for a voltage from displacement. It nudges the voltage toward a temperature-safe limit in bounded steps, using error magnitude to soften the step near target.
- In the real implementation, that final "Choose next voltage move" block is split across outer/inner piezos plus anchor-point logic. This diagram intentionally collapses all of that into one actuator.

## Code Map

- Wrapper startup and channel API: [instrument_strainController.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/instrument_strainController.m:41)
- Public watchdog channels exposed to the rack: [instrument_strainController.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/instrument_strainController.m:100)
- Wrapper `GET`/`SET`/`CHECK` forwarding: [instrument_strainController.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/instrument_strainController.m:335)
- Main watchdog loop: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:240)
- Measurement and state update: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:258)
- Overload / at-target decision: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:277)
- Real branch logic that this diagram simplifies away: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:320)
- Command handling for `activeControl`, tare, and direct access: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:605)
- Voltage bounds and displacement conversion helpers: [strainWatchdog.m](/c:/Users/Thomas/Desktop/sm-dev/code/instruments/@instrument_strainController/private/strainWatchdog.m:784)
