# Building LockIn

## Prerequisites

- macOS 13+
- Xcode 15+ (`xcode-select --install` for the command-line tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Common tasks

The Xcode project is generated from `project.yml`, so run `make gen` after adding or removing files.

```
make gen      # regenerate LockIn.xcodeproj from project.yml
make build    # build app + daemon + agent (unsigned)
make test     # run all unit tests
make run      # build and launch the app
make clean    # remove build artifacts
```

## What works unsigned

`make test` and `make run` need no code signing. Tests cover the scheduler, clock-tamper
logic, the block engine wrapper, and list import. `make run` launches the full UI.

## What needs signing

The system-level blocking (the background service that enforces blocks across all
browsers and survives reboot) installs via macOS's login-items mechanism, which
requires a Developer ID signing identity. To build a signed copy, set your team in
`project.yml` (`DEVELOPMENT_TEAM`) and build the `Release` configuration in Xcode.
The remaining on-device validation steps are tracked in `Tests/Validation/RISKS.md`.
