# Building LockIn

## Prerequisites

- macOS 13+
- Xcode 15+ (`xcode-select --install` for the command-line tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Common tasks

The Xcode project is generated from `project.yml`, so run `make gen` after adding or removing files.

```
make gen      # regenerate LockIn.xcodeproj from project.yml
make build    # build signed app + daemon + agent (installable)
make test     # run all unit tests
make run      # build and launch the app
make release  # build a signed, notarized LockIn.dmg (maintainers — see RELEASE.md)
make clean    # remove build artifacts
```

## Signing

`make build` signs with the team set in `project.yml` (`DEVELOPMENT_TEAM`). Signing is
required for the background service that enforces blocks across browsers and survives
reboot — macOS won't register it from an unsigned build. If you fork this, change
`DEVELOPMENT_TEAM` to your own Apple Developer Team ID.

`make test` needs no signing.

## Installing the background service

On first launch, starting a lock or schedule prompts you to install the helper, then to
approve it in **System Settings → General → Login Items & Extensions**. On-device
validation steps are tracked in `Tests/Validation/RISKS.md`.

## Releasing

Producing a downloadable, notarized build is a separate maintainer process — see
[RELEASE.md](RELEASE.md).
