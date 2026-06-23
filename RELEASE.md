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

### Required repository secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID (the OU on your signing cert) |
| `APPLE_ID` | the Apple ID email of your developer account |
| `APPLE_APP_SPECIFIC_PASSWORD` | an app-specific password from appleid.apple.com |
| `DEVELOPER_ID_CERT_P12` | base64 of your exported Developer ID Application `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | the password set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any string; used to create a temporary CI keychain |

### One-time signing setup

1. **Developer ID Application certificate** — Xcode → Settings → Accounts → your team →
   Manage Certificates → **+** → *Developer ID Application*.
2. **Export it** — Keychain Access → login → My Certificates → right-click the cert →
   Export as `cert.p12` (set an export password).
3. **Base64 it** for the secret: `base64 -i cert.p12 | pbcopy`
4. **App-specific password** — appleid.apple.com → Sign-In and Security →
   App-Specific Passwords → generate one for notarization.

## Local release

With a Developer ID Application cert in your keychain:

```
make release VERSION=1.0.0 APPLE_ID=you@example.com APPLE_PASSWORD=abcd-efgh-ijkl-mnop
```

This builds, signs, notarizes, staples, and produces `LockIn.dmg` in the project root.
Upload it to a GitHub Release manually.
