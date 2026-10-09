# Releasing GoldenIce

GoldenIce updates itself with Sparkle, like Ice. Until the steps below are done it still points
at upstream Ice's feed, which is harmless: GoldenIce's build numbers (2700 and up) are higher
than any upstream build, so it is never offered one.

## One-time setup

1. **Update key.** Run Sparkle's `generate_keys` (in the Sparkle package's `bin` folder after a
   build, e.g. `…/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`). It stores the
   private key in your keychain and prints the public key.
2. **Point the app at GoldenIce's feed.** In `Ice/Resources/Info.plist` set
   - `SUFeedURL` to `https://github.com/scoopy115/GoldenIce/releases/latest/download/appcast.xml`
   - `SUPublicEDKey` to the public key from step 1.

   Do both in the same release: a build with the new feed but upstream's key cannot verify
   GoldenIce's updates, and one with the new key but upstream's feed has nothing to install.
3. **Notarization.** `xcrun notarytool store-credentials GoldenIce` with your Apple ID and an
   app-specific password, so the release script can notarize without asking.

## Each release

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project.
2. Run `Scripts/release.sh`. It builds a signed, notarized zip and an appcast in `build/releases`.
3. Create a GitHub release tagged `v<version>` and attach both files.

Installed copies find the update the next time Sparkle checks.
