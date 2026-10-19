# NIZ X87EC configuration protocol

Reverse-engineered from the vendor's Windows tool (`X87EC.exe` + `X87ECHWI.dll`, 2022-08)
and checked against an X87EC(S)BLe (`X87EC-RGB`, firmware `X87EC(S)BLe;V1.3.1;V1.0;`).

## USB

| Mode | VID:PID | Interfaces |
|------|---------|------------|
| Mac  | `05AC:0220` (pretends to be Apple) | 0 keyboard, 2 consumer/NKRO/mouse. **No config interface.** |
| Win  | `0483:5031` / `5131` / `5231` / `5331` (one per X87EC variant) | 0 keyboard, **1 vendor (config)**, 2 consumer/NKRO/mouse |

Fn + Left Alt toggles Win/Mac. The new mode only takes effect after a USB replug.

Interface 1: usage page `0x8C`, usage 1, 64-byte input and output reports, no report IDs,
interrupt IN `0x82` and OUT `0x01`. On macOS `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, 0, …)`
works without special permissions.

Every report is 64 bytes. Host commands are `00 <cmd> 00 …`.

## Commands

| Cmd  | Direction | Meaning |
|------|-----------|---------|
| `F9` | → ← | Version. Reply `00 F9 <ASCII…>` e.g. `X87EC(S)BLe;V1.3.1;V1.0;` |
| `F2` | → ←… | Read keymap. Device streams `F0` records, then a report of 64 × `F6`. |
| `F1` | → →… | Write keymap. Host sends `F0` records, then `00` + 63 × `F6`. No replies. |
| `E2` | → ←… | Read per-key lighting: `00 E0 <len> <data…>` chunks, then 64 × `E6`. |
| `E1` | → →… | Write lighting: same `E0` chunks (61 bytes each), then 64 × `E6`. |
| `E3` | → ←… | Read keystroke counters: `00 E3 <len> <data…>` chunks, then 64 × `E6`. |
| `:`  | → … | Firmware update: Intel-HEX lines as `00 3A <decoded bytes>` (not implemented here). |

Sending reports back-to-back can make the firmware drop some (seen with `F9`);
a few milliseconds between reports is enough.

## Key banks and layers

The keyboard keeps a **factory layout** and a **programmable layout**. The key at Fn + Pause
(code `0x9F`, "Programmable Keyboard") switches between them.
`F2` reads the active one; `F1` always writes the programmable one.

Each bank has 6 layers of 87 keys. Layer 1 is base, 2 is Fn; on a stock keyboard 3–4 and
5–6 are copies of 1–2 (their purpose isn't confirmed, probably other connection modes).
The firmware **clears any layer not sent** in an `F1` session. The Windows tool sends only
layers 1–2, so this tool sends all 6 and mirrors base/Fn into 3–6.

## Key record (`F0`)

```
byte  0     00
      1     F0
      2     layer (1-based)
      3     key position (1-based, see below)
      4     type
```

| Type | Meaning | Rest of the record |
|------|---------|--------------------|
| 0 | key / chord | `[5]` count, `[6…]` codes. Count 0 = unassigned. |
| 1 | repeat ("emulate") | `[5..6]` interval ms (BE), `[7]` count, `[8…]` codes |
| 2 | macro, play N times | macro header, below |
| 3 | macro, play while held | |
| 4 | macro, press to start/stop | |

Macro records span `ceil(size / 53)` reports. Each repeats the 11-byte header:

```
[5]     cycles (type 2)
[6]     1 = per-step delays, 0 = fixed delay
[7..8]  fixed delay in ms (BE)
[9..10] data size in bytes (BE)
[11..]  up to 53 data bytes
```

Data is one code per step, or with per-step delays `code, C8, delayHi, delayLo` per step.
(`C8` is constant in the Windows tool; its meaning is unknown.)

## Lighting

261 bytes: 87 × `R G B` in key-position order. These are the colours of the custom
backlight effect (Fn + ` on the stock layout).

## Counters

348 bytes: 87 × little-endian `uint32`, key-position order.

## Key positions

1 Esc, 2–13 F1–F12, 14 \`, 15–24 1–0, 25 -, 26 =, 27 Backspace, 28 Tab, 29–38 Q–P, 39 [, 40 ],
41 \\, 42 Caps, 43–51 A–L, 52 ;, 53 ', 54 Enter, 55 LShift, 56–62 Z–M, 63 `,`, 64 ., 65 /,
66 RShift, 67 LCtrl, 68 LWin, 69 LAlt, 70 Space, 71 RAlt, 72 Fn, 73 Menu, 74 RCtrl,
75 PrtSc, 76 ScrLk, 77 Pause, 78 Ins, 79 Home, 80 PgUp, 81 Del, 82 End, 83 PgDn,
84 ↑, 85 ←, 86 ↓, 87 →.

## Key codes

`1–74` are the same as positions 1–74 (72 = RWin). Then `75–77` power/sleep/wake,
`78–90` PrtSc…→, `91–107` NumLock and keypad, `0xCC` ISO extra key.

| Range | Group |
|-------|-------|
| `6C–7D` | media: next, prev, stop, play/pause, mute, vol+, vol−, media, mail, calc, my computer, WWW search/home/back/forward/stop/refresh/favourites |
| `7E–86` | mouse: move ←→↑↓, left/right/middle click, wheel up/down |
| `87–B2` | keyboard functions: backlight, effects, brightness, keyboard lock, trigger point, Ctrl/Caps swap, Win lock, Fn lock, Win/Mac (`9B`), Fn (`9C`), programmable (`9F`), wired/wireless (`A7`), BT 1–5, game, ECO … |

Full names are in `Sources/NIZKit/KeyCodes.swift`.
