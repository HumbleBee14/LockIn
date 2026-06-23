# LockIn — Empirical Risk Validation (hardware spikes)

These four Phase 0 risk spikes **cannot be run headlessly** — they need Developer ID
signing, a real Mac with root, and live browsers/network. They were built and left
ready to run; record findings here. Each gates a downstream Phase 1–3 decision.

**Run order:** 1 → 2 → 3 → 4. Risk 1 (signing) unblocks 3; Risk 2 is independent.

---

## Prerequisite — Developer ID signing

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Apple Developer Team ID.
2. In `Shared/XPCRequirements.swift`, replace `teamIdentifier = "REPLACE_TEAMID"` with the
   same Team ID (the OU on your Developer ID leaf cert).
3. `xcodegen generate`
4. Build signed:
   `xcodebuild -project LockIn.xcodeproj -scheme LockIn -configuration Release build`
   (Developer ID Application identity selected). Confirm `** BUILD SUCCEEDED **`.

---

## Risk 1 — Does root-daemon registration prompt for admin auth? (gates §8 "no password" copy)

Run the signed app on a clean account/VM, click **Install**, observe.

- Daemon registration prompt observed: `<YES (admin auth) | NO (Login Items only)>`
- Agent registered promptlessly: `<YES | NO>`
- `SMAppService.Status` before approval: `<...>`  after approval: `<...>`
- Onboarding copy decision: `<"one admin authorization at install" | "no password, approve in Login Items">`
- Tested on: macOS `<version>`, `<Apple Silicon | Intel>`

---

## Risk 2 — Vendored pf/hosts engine actually blocks on current macOS (acceptance #2 canary)

The daemon's smoke entry point (added in Phase 1, env-guarded `LOCKIN_SMOKE=1`) blocks
`example.com` for 60s then clears. Run as root, check three browsers.

- `sudo LOCKIN_SMOKE=1 ./lockind`
- example.com blocked in Safari / Chrome / Firefox: `<YES all | partial: ...>`
- DNS flush dance needed adjustment: `<NO | YES: ...>`
- pf anchor behavior changed vs SelfControl assumptions: `<NO | YES: ...>`
- Verdict: `<engine usable as-is | needs fix before Phase 1: ...>`

> NOTE: the pf anchor is still SelfControl's `org.eyebeam` (see DECISIONS.md D7 — renamed
> to a LockIn anchor in Phase 1). Run this canary BEFORE the rename to isolate engine
> behavior from the rename, then re-run after.

---

## Risk 3 — Code-signing-authorized XPC round-trip works end to end

With the signed, registered daemon, the app calls `getVersion` over XPC.

- Raw NSXPC code-signing auth round-trip works (signed app gets version back): `<YES | NO + error>`
- An ad-hoc re-signed copy is REJECTED by `shouldAcceptNewConnection`: `<YES rejected | NO leaked>`
- Decision for Phase 1: `<keep raw NSXPC | adopt trilemma-dev/SecureXPC>`
- Rationale: `<...>`

---

## Risk 4 — LaunchConstraint / SpawnConstraint support on macOS 13–15 (tier 5b)

Add a `LaunchConstraint` dict to `lockind.plist` (require the signing identifier),
re-register on each reachable OS.

- macOS 13: `<supported | not>` | macOS 14: `<...>` | macOS 15: `<...>`
- Keys that worked: `<...>`
- Phase 3 decision: `<ship 5b as designed | downgrade/skip>`
