# Developing NoNappa

Requires macOS 13+, Xcode Command Line Tools, and network access on the first build. `build.sh` downloads checksum-pinned Sparkle 2.10.1 from its official GitHub release; no package manager or Xcode project is needed.

```sh
git clone https://github.com/archestra-ai/nonappa.git
cd nonappa
bash test.sh
bash build.sh --install
```

Local builds are ad-hoc signed and do not enable the updater without `SPARKLE_PUBLIC_ED_KEY`. They install to `~/Applications/NoNappa.app`. Ordinary production updates use Sparkle; local rebuilds still need `build.sh --install`.

The root-owned sleep helper accepts only predefined commands from the approved user and exact app signature over XPC. Updating or rebuilding the app can require approving **Set Up Sleep Controls…** again. Updates never migrate, replace, or broaden helper permissions silently. Existing timed restoration runs independently of the app.

## Safe local UI review

Build without installing, then launch fixture mode:

```sh
bash build.sh
open -n "$PWD/build/NoNappa.app" --args --preview-state normal
```

The window is titled **NoNappa — Safe UI Preview**. Controls simulate sessions in memory; this mode never installs the helper, changes sleep settings, or registers login items. Preview preferences are separate from the installed app. Supported states: `normal`, `awake`, `timed`, `error`, `setup`, and `busy`. Quit from the gear menu. To render all compact layouts and exit:

```sh
open -n "$PWD/build/NoNappa.app" --args --preview-state normal --snapshot-directory "$PWD/build/screenshots"
```

## Tests

`bash test.sh` checks saved settings, status parsing, timer restoration, failure rollback, indefinite mode, command validation, and signed helper installation. The UI model suite additionally checks session transitions, reopening, cancellation, read recovery, and control guards against in-memory power fixtures. System-changing process boundaries are substituted. Actual authorization, privileged XPC, lid-close behavior, and reboot recovery require manual verification.

## Uninstall

Restore sleep, disable **Launch at login**, and quit the app. Remove the helper in Terminal, then delete `~/Applications/NoNappa.app`:

```sh
sudo launchctl bootout system/com.nonappa.restore
sudo rm -f /Library/LaunchDaemons/com.nonappa.restore.plist
sudo launchctl bootout system/com.nonappa.helper
sudo rm -f /Library/LaunchDaemons/com.nonappa.helper.plist
sudo rm -rf /Library/PrivilegedHelperTools/com.nonappa.helper
```

“Service not found” means that job is already absent.


## Packaging

`bash scripts/package.sh` produces an arm64 + x86_64 ZIP in `build/release/`. `CODE_SIGN_IDENTITY` optionally selects an existing signing identity; the default is ad-hoc signing for development. Distribution setup is in [RELEASING.md](RELEASING.md).
