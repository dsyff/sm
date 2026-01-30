# Communication Guide (USB CDC Serial)

This firmware exposes a USB CDC serial interface and accepts ASCII commands
terminated by newline (`\n`). Carriage returns (`\r`) are ignored. Responses
always end with CRLF (`\r\n`).

## Serial Settings
- Port: USB CDC device created by the Pico 2
- Baud: 115200 (USB CDC ignores baud, but use 115200 for compatibility)
- Line ending: send `\n` (LF). `\r\n` also works.

## Commands
Commands are case-insensitive. Leading/trailing whitespace is ignored.

- `*IDN?`
  - Response: `RPI,PICO2,WS2811,1.0`
- `COLOR r,g,b`
  - Sets LED color; `r`, `g`, `b` are integers 0..255.
  - Separators can be commas and/or spaces.
  - Response: `OK` on success, `ERR` on parse/range error.
- `OFF`
  - Sets `r=g=b=0`.
  - Response: `OK`
- `GET`
  - Response: `COLOR r,g,b` (current stored color)
- `HELP`
  - Response: a brief command list

## Errors and Limits
- Unknown command: `ERR`
- Empty line: ignored
- Line too long: input is flushed to newline, then `ERR` is returned
  (max line length is 95 characters before `\n`).

## Example Session
```
> *IDN?
RPI,PICO2,WS2811,1.0
> COLOR 255, 128, 64
OK
> GET
COLOR 255,128,64
> OFF
OK
```

## Notes
- `LED_PIN` and the WS2811 timing selection (`WS2811_800KHZ`) are defined at
  the top of `WS2811_LED_pico_2.ino`.
