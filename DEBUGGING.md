# Debugging WIM

WIM has a built-in debug capture that writes a timestamped log to disk. It
exists so that a bug report can include *what actually happened*, including
everything that fires during login -- long before a slash command could be
typed.

## Debug levels

| Level | Command | What it records |
|-------|---------|-----------------|
| 0 | `/wim debug 0` | Nothing (default). Zero overhead. |
| 1 | `/wim debug 1` | WIM's own diagnostic messages (module enable/disable, history conversion, channel/community bookkeeping, …). Shown in the chat frame **and** written to the log. |
| 2 | `/wim debug 2` | Everything from level 1, **plus** a raw trace of every chat-related event the client delivers (whispers, channels, club/community plumbing, channel-list churn), with arguments, **and a `SETTING` line for every option change committed from either options UI** (`SETTING [classic\|modern] <key> = <value>`). Trace lines go to the log only -- they are far too noisy for the chat frame. |

`/wim debug` with no number toggles between 0 and 1. The level **persists
across logout/login**, which is deliberate: most of the interesting behavior
happens during the login sequence, so you set the level once, then log out
and back in to capture it.

`/wim debugclear` empties the captured log (useful between test attempts).

## Where the log lives

The log is a per-character SavedVariable, `WIM3_DebugLog`, written by the
client **on logout or `/reload`** -- it is not on disk in real time. Find it
at:

```
WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/WIM.lua
```

Each line is prefixed with a wall-clock timestamp with millisecond
resolution (e.g. `08/14 09:12:03.481`), so event ordering within a single
frame is preserved. Whenever capture starts, a header line records the WIM
version, client build, interface number and locale:

```
=== WIM 3.18.0 | level 2 | WoW 12.1.0 (build 58238, interface 120100) | enUS | Charname-Realm ===
```

The buffer is a bounded ring (6000 lines, 500 characters per line): long
sessions overwrite the oldest half, so capture what you need and copy it out
promptly. Because the log is per-character it can never bloat the
account-wide settings file.

Trace lines never contain protected chat content: values the client marks as
secret are logged as `<secret>`.

## Including a log in a bug report

1. `/wim debug 2` (or `1` if the issue isn't event-related).
2. `/wim debugclear` to start clean.
3. Reproduce the problem. If it involves login behavior, log fully out and
   back in with the level already set.
4. Log out (or `/reload`) so the client writes the file.
5. Open `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/WIM.lua`,
   copy the `WIM3_DebugLog` `lines` block (or attach the whole file), and
   paste it into the issue inside a code fence. Include the `===` header
   line -- it carries the version information the report needs.
6. `/wim debug 0` when you're done, so the log stops accumulating.

What a good capture shows the maintainer: the exact order the client
delivered events in, what arguments they carried, and which of WIM's
handlers ran -- three things that cannot be reconstructed from a screenshot
or a description after the fact.

## Related diagnostic commands

- `/wim focusstreams` -- A/B switch for WIM's community-stream focus pass at
  login (on by default; without it the client refuses sends to
  community-backed channels while WIM is loaded).
- `/wim channelrepair` -- opt-in, experimental: on logins where the community
  stream focus lands late, remove and re-add community channels to
  ChatFrame1. This is the only WIM feature that mutates saved chat-window
  configuration, which is why it is off unless explicitly enabled.
