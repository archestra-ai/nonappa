# Releases and automatic updates

One release workflow, no update server: Release Please maintains a version/changelog PR; merging that PR creates a **draft** release. The same workflow tests and builds a universal app, signs and notarizes it, staples the ticket, signs the final ZIP with Sparkle Ed25519, uploads the ZIP/feed/checksum, and publishes only after all steps succeed. The feed is the `appcast.xml` asset at GitHub’s stable `releases/latest/download` URL. A single latest full update is enough; there are no deltas, installer packages, or extra hosting services.

## One-time setup

Publishing is disabled until repository variable `NONAPPA_RELEASES_ENABLED` is `true`. Create a GitHub environment named `release`, restricted to the main branch, for the signing secrets below. Do the following before enabling it:

1. Allow **this repository** to use the existing `ARCHESTRA_RELEASER_GITHUB_APP_ID` and `ARCHESTRA_RELEASER_GITHUB_APP_PRIVATE_KEY` organization secrets, and ensure the app installation includes NoNappa. Its token creates release PRs that trigger normal checks. `GITHUB_TOKEN` alone does not trigger those PR workflows.
2. Use an existing **Developer ID Application** certificate with its private key, exported as a password-protected P12. Set secret `NONAPPA_DEVELOPER_ID_P12` to its base64 encoding and `NONAPPA_DEVELOPER_ID_PASSWORD` to its export password. Set variable `NONAPPA_CODE_SIGN_IDENTITY` to the full identity name. This workflow does not create certificates or change provisioning.
3. Create an App Store Connect notarization API key with appropriate notarization access. Set secret `APPLE_NOTARY_KEY_P8` to the P8 contents, and variables `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID`. The workflow imports signing material only into an ephemeral CI keychain and deletes it afterward.
4. Generate a dedicated Sparkle update-signing seed locally, preserving a secure backup:

   ```sh
   mkdir -p .secrets
   swift scripts/update-key.swift generate .secrets/sparkle-private .secrets/sparkle-public
   gh secret set --env release SPARKLE_PRIVATE_ED_KEY < .secrets/sparkle-private
   gh variable set SPARKLE_PUBLIC_ED_KEY < .secrets/sparkle-public
   ```

   This uses CryptoKit and files with private permissions; it never touches the login Keychain. `.secrets/` is ignored. Never commit or print the private seed. The workflow checks that the public and private keys match before building. Keep the same public key across releases; rotating it requires a supported Sparkle migration, not overwriting it.
5. Enable `NONAPPA_RELEASES_ENABLED=true`, then run the Release workflow once. Future pushes to main update the release PR. Merge release PRs through normal checks when ready; they are not auto-merged.

No production keys, app permissions, certificates, or repository variables are installed by the source changes alone.

## Versions and retries

Use Conventional Commits (`feat:`, `fix:`) and squash release PRs with Release Please’s generated title. `version.txt` is the single source of the app’s short and bundle versions. The manifest starts at 1.0.0, matching the previous local build; bootstrap commit `611c8a3` is the merged UI baseline. New functionality starts the first automated minor release.

A failed build/notarization/upload leaves the release as a draft, leaving the previous latest feed intact. To retry, manually run **Release** with the draft’s version (without `v`); it resolves the existing immutable tag and rebuilds that exact source. Already-published versions are rejected. Do not merge the next release until a failed draft has been resolved.

The downloaded archive is universal and uses `ditto` to preserve framework symlinks. Its final archive is signed **after** notarization and stapling; the feed points to that exact version’s asset. SHA256SUMS is an additional download-integrity aid, not a substitute for Sparkle signatures or notarization.

## Local validation

`bash test.sh` checks core/helper/model behavior. `bash scripts/test-release.sh` type-checks the production updater, builds universal developer slices, verifies runtime launch, packaging, versions, actual Ed25519 signing, malformed-feed inputs, and tampered-archive rejection using disposable fixture keys. It never uploads, installs an update, prompts for helper approval, or changes the Mac’s power/login settings.

Production Sparkle loading with Developer ID library validation, Apple notarization, release-PR creation, publication, and a real two-version Sparkle installation need the configured credentials and a first release. They have not been validated by a local fixture run.
