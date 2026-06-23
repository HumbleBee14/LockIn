# LockIn

A macOS desktop focus blocker that blocks distracting **websites and apps on an automatic recurring schedule** — and **cannot be turned off until the scheduled window ends**. No browser extension: website blocking works at the system level (`/etc/hosts` + `pf`) across every browser and app.

The promise: *set it once — at 10pm every night the distractions go dark across the whole system, and there's no off switch until 7am. No willpower, no per-night setup, no password prompt.*

## Why

Most blockers fail at least one of: no extension required, works in every browser, fires automatically on a schedule, and is genuinely un-bypassable once active. LockIn aims for the strongest *practical* hard-lock on a self-owned Mac — survive kill / quit / delete / reboot, and resist clock tampering — while being honest about the ceiling (a determined root user with a terminal can always tear down their own machine; we beat impulse, not that).

## Architecture (brief)

Three components:
- **`LockIn.app`** — SwiftUI UI (schedule grid, block-set editor, status). The only way you interact with it.
- **`lockind`** — a root LaunchDaemon (installed once via `SMAppService`) that owns the schedule, the lock state, and the website-blocking engine. No "stop" method exists — its absence is the lock.
- **`lockin-agent`** — a per-user helper that enforces app blocking (a labeled *soft* deterrent; website blocking is the real hard lock).

Website blocking is built on top of [SelfControl](https://github.com/SelfControlApp/selfcontrol)'s proven hosts/pf engine; LockIn adds the scheduler, clock-tamper resistance, app blocking, and a native UI that SelfControl lacks.

## Status

MVP feature-complete (Phases 0–3) and building green on macOS 13+; the lock core,
SwiftUI UI, and app-blocking agent are all in place with unit tests passing. The
remaining work is **hardware validation** — the Developer-ID-signed install flow,
the pf/hosts engine canary across browsers, the code-signing-authorized XPC
round-trip, launch-constraint support, and the daemon→agent push direction — all
documented in [`Tests/Validation/RISKS.md`](Tests/Validation/RISKS.md) with run
procedures, since they need a real Mac with root and signing.

Autonomous build decisions are logged in [`DECISIONS.md`](DECISIONS.md).

## License

**GPLv3** (see [`LICENSE`](LICENSE)). LockIn incorporates and builds on SelfControl's hosts/pf engine, which is GPLv3; LockIn inherits that license. Keep this code isolated from any permissively-licensed modules.

## Credits

Built with knowledge from SelfControl, HammerControl, auto-selfcontrol, Cold Turkey, and the macOS privileged-helper community. Full attribution will accompany the first public release.
