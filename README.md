# davecal

A small native macOS calendar. It reads and writes every account already set
up in the macOS Calendar app (Fastmail, Microsoft 365, iCloud and so on)
through Apple's EventKit, so there is no account setup of its own.

- Month view with a strong grid, today as a solid block, and each all-day
  event cut to the day cells it covers.
- Week view with an hourly grid, overlapping events side by side, and a
  line for the current time.
- Sidebar with one checkbox per calendar. Hold a calendar name to see only
  that calendar. Below it, the next two weeks of events.
- An event window that stays open until you Save, Close, Discard or Delete.
  Repeating events can be deleted one occurrence, from here on, or entirely.

## Shortcuts

| Keys | Does |
| --- | --- |
| Cmd N | New event |
| Cmd T | Go to today |
| Cmd Left / Right | Previous / next month or week |
| Cmd 1 / Cmd 2 | Month / week view |
| Ctrl Cmd S | Show or hide the sidebar |
| Return / Esc | Save and close / Close in the event window |

Double-click an empty day or time slot to create an event there. Double-click
an event to open it. Click a day's header strip for the full list of that day.

## Building

Needs macOS 15 or later and the Swift toolchain (Xcode or Command Line Tools).

```bash
make run
```

That builds a release binary, wraps it as `davecal.app` with an ad-hoc
signature, and opens it. macOS asks for calendar access on first launch.
