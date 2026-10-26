# NoNappa

A tiny native macOS menu bar app that keeps your Mac awake with the lid closed.

- Stay awake for 15 minutes to 8 hours, or until you turn it off.
- Timed sessions restore sleep even if the app quits or the Mac restarts.
- Saved preferences, launch at login, and an OpenAPPA mascot in your menu bar.
- One-time helper approval; no password prompts for everyday sleep controls.

## Build and run

Requires macOS 13+ and Xcode Command Line Tools. No external dependencies.

```sh
git clone https://github.com/joeyorlando/nonappa.git
cd nonappa
bash test.sh
bash build.sh --install
```

The app installs to `~/Applications/NoNappa.app`. Click its menu bar icon, choose **Set Up Sleep Controls…**, and approve the helper installation. Select a duration and choose **Keep Awake**. During a session, **Restore Sleep** is the primary action; the gear menu lets you change duration. Launch at login and Quit are in the gear menu and the menu-bar icon’s right-click menu. Launch at login is opt-in.

The root-owned helper accepts only predefined sleep commands from the approved user and exact app signature over XPC. It never stores your password. Rebuilding or updating the app may require approving the helper again. Keep the Mac ventilated while running with the lid closed; support depends on macOS and hardware behavior for `pmset disablesleep`.

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

## License and credits

Code is licensed under [AGPL-3.0-only](LICENSE), retained from its original repository. The mascot comes from [OpenAPPA branding](https://www.openappa.com/branding); credit belongs to OpenAPPA. This project does not grant trademark rights to the mascot.
