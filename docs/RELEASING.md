# Releasing GoldenIce

GoldenIce updates itself in the app with Sparkle, as Ice did: it reads a feed, offers the new
version, and installs it with one click. The feed is the `appcast.xml` attached to the latest
GitHub release:

    https://github.com/scoopy115/GoldenIce/releases/latest/download/appcast.xml

## One-time setup (done)

- **Update key.** GoldenIce's EdDSA key is in the login keychain under the account `goldenice`
  (Sparkle's `generate_keys --account goldenice`). Its public half is `SUPublicEDKey` in
  `Ice/Resources/Info.plist`. Keep the private half safe: without it, installed copies cannot
  verify new versions. Export a backup with `generate_keys --account goldenice -x <file>` and
  keep that file off the repository.
- **Notarization.** `Scripts/release.local.env` (ignored by git) names the notarytool keychain
  profile: `NOTARY_PROFILE=<profile>`. The Developer ID certificate is found in the keychain.

## Each release

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project. Sparkle compares
   `CURRENT_PROJECT_VERSION`, so it must go up every time.
2. Run `Scripts/release.sh --appcast`. It builds, signs and notarizes the app and a DMG, and
   writes `appcast.xml`, all in `build/releases` (ignored by git). Keep the previous
   `appcast.xml` there, so the new one lists earlier versions too.
3. On GitHub, create a release tagged `v<version>` (not a draft or pre-release, or it is not
   "latest") and attach the DMG and `appcast.xml`.

Installed copies find the update at their next check, or at once with "Check for Updates".
