# Releasing LockIn

LockIn ships as a signed, notarized `.dmg` attached to a GitHub Release. Releases are
cut by pushing a version tag; a GitHub Actions workflow builds, signs, notarizes, and
publishes automatically. You can also build a release locally.

## Versioning

Tags follow [semver](https://semver.org): `vMAJOR.MINOR.PATCH`.

- **PATCH** (`v1.0.0 → v1.0.1`) — bug fixes only
- **MINOR** (`v1.0.0 → v1.1.0`) — new features, backward-compatible
- **MAJOR** (`v1.0.0 → v2.0.0`) — breaking changes

The tag is the single source of truth: the app's displayed version is derived from it
(`v1.2.0` → `1.2.0`). There is no auto-increment — pick the number based on what changed.

## Automated release (GitHub Actions)

```
git tag v1.0.0
git push origin v1.0.0
```

The `Release` workflow builds, signs with Developer ID, notarizes, staples, and attaches
`LockIn.dmg` to a new GitHub Release. It can also be run manually from the Actions tab.

## Local release

With a Developer ID Application cert in your keychain:

```
make release VERSION=1.0.0 APPLE_ID=you@example.com APPLE_PASSWORD=abcd-efgh-ijkl-mnop
```

This builds, signs, notarizes, staples, and produces `LockIn.dmg` in the project root.
Upload it to a GitHub Release manually.
