# NoNappa

**LID DOWN. GAME ON.** A tiny macOS menu-bar app that keeps your Mac awake with the lid closed, for a timer or until you stop it.

## Install

Download the universal ZIP from [Releases](https://github.com/archestra-ai/nonappa/releases/latest), unzip it, and drag **NoNappa.app** into Applications. Requires macOS 13+; works on Apple Silicon and Intel.

The first downloadable release is pending the [one-time signing setup](docs/RELEASING.md). Until then, use the developer build below.

Open NoNappa, approve **Set Up Sleep Controls…**, choose a duration, and click **Keep Awake**. Click **Restore Sleep** to stop. Keep your Mac ventilated while running with the lid closed; support depends on macOS and hardware.

Sparkle checks for updates with your permission; automatic installation is optional in the gear menu. **Check for Updates…** is in the gear menu and menu-bar icon’s right-click menu. After an update, sleep controls may need administrator approval again. Launch at login is optional.

## Develop

```sh
git clone https://github.com/archestra-ai/nonappa.git
cd nonappa
bash test.sh
bash build.sh --install
```

Requires Xcode Command Line Tools. See [development and uninstall instructions](docs/DEVELOPING.md) or [release setup](docs/RELEASING.md).

## License and credits

[AGPL-3.0-only](LICENSE). Mascot by [OpenAPPA](https://www.openappa.com/branding). Sparkle is distributed under its [license](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE).
