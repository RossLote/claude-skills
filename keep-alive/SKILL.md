---
name: keep-alive
description: Keep this session's prompt cache warm while the user is away — start a 50-minute shell timer, restart it every time it goes off and do nothing else, until the user writes again; then cancel it. Started only by the user typing "/keep-alive".
disable-model-invocation: true
allowed-tools: Bash(sleep 3000)
---

# Keep alive

The user is stepping away, usually close to the session's usage limit, and wants to come
back to this session with its prompt cache (one hour) still valid. A background shell
timer that wakes the session every 50 minutes keeps it valid. This needs no thought: do
not reason, plan, check, read, summarise or tidy anything (user, 2026-10-30).

**On /keep-alive, and every time the timer goes off:** one Bash call and nothing else:
`sleep 3000` with `run_in_background: true` and the description `Keep-alive timer`. Then
reply `Keep-alive: timer running.` and end the turn. If a timer is already running when
/keep-alive is typed, start no second one; just reply.

Only a background shell timer. Never ScheduleWakeup, CronCreate, /loop, Monitor or a
foreground sleep: those have failed before and let the cache expire. Never change model
or effort: another model reads another cache.

**Any other notification while the user is away** (an agent finishing, another background
command): do not act on it. Reply `Keep-alive: <what finished>, left for later.` and end
the turn; the timer is still running.

**When the user writes again** (their own message, not a notification): stop the latest
timer with TaskStop (load it with ToolSearch if it is deferred), then answer them as
normal and name anything that finished while they were away.
