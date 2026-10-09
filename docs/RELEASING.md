# Releasing GoldenIce

GoldenIce updates itself in the app with Sparkle, as Ice did: it reads a feed, offers the new
version, and installs it with one click. The feed is the `appcast.xml` attached to the latest
GitHub release:

    https://github.com/scoopy115/GoldenIce/releases/latest/download/appcast.xml

## Automatic releases

Every push to `main` is released by GitHub Actions (`.github/workflows/release.yml`), unless it
only changes documentation. The workflow:

1. numbers the release: the project's `MARKETING_VERSION` without its last number is the base
   (`0.11.13-goldengate`), and the release gets the next number on it (`…goldengate.2`,
   `…goldengate.3`). The build number is 2700 plus the workflow's run number, so it only goes
   up. Nothing is committed back; to start a new base, change `MARKETING_VERSION` in the project.
2. builds GoldenIce with Developer ID, notarizes the app and a DMG, and writes a new
   `appcast.xml` that also lists the earlier versions;
3. publishes a GitHub release tagged `v<version>` with the DMG, the zip and `appcast.xml`, with
   notes generated from the commits.

Installed copies find the update at their next check, or at once with "Check for Updates".

### Secrets

The signing identity is never in the repository. The workflow takes it from the repository's
encrypted secrets (Settings → Secrets and variables → Actions → New repository secret), which
GitHub does not show to anyone, does not print in logs, and does not give to forks:

| Secret | What goes in it |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID Application certificate with its private key, exported from Keychain Access as a `.p12`, then base64: `base64 -i GoldenIce.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the `.p12` |
| `NOTARY_KEY` | The contents of an App Store Connect API key (`AuthKey_XXXX.p8`), made in App Store Connect → Users and Access → Integrations → Team Keys, with the Developer role |
| `NOTARY_KEY_ID` | That key's Key ID |
| `NOTARY_ISSUER` | The Issuer ID shown above the list of keys |
| `SPARKLE_PRIVATE_KEY` | The update key: `generate_keys --account goldenice -x sparkle.key`, then the contents of `sparkle.key` |

Instead of an API key, notarization can use an Apple ID: set `APPLE_ID`, `APPLE_APP_PASSWORD`
(an app-specific password from account.apple.com) and `APPLE_TEAM_ID`, and leave `NOTARY_KEY`
unset.

Delete the exported `.p12`, `.p8` and `sparkle.key` files once they are in the secrets, or keep
them somewhere safe off the repository. Without the update key, installed copies cannot verify
new versions.

## Releasing by hand

`Scripts/release.sh --appcast` does the same on a Mac, with the Developer ID certificate from the
keychain and the notarytool keychain profile named in `Scripts/release.local.env` (ignored by
git): `NOTARY_PROFILE=<profile>`. It writes everything to `build/releases`; the release on GitHub
is then made by hand. Raise `CURRENT_PROJECT_VERSION` first, or pass `MARKETING_VERSION` and
`BUILD_NUMBER` in the environment: Sparkle compares the build number, so it must go up every time.
