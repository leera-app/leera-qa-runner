# leera-qa-runner

The Leera QA runner runs your automated test cases on machines you own — a laptop, a
Mac mini under a desk, a Linux server or your CI — and reports step results, screenshots,
video and debug logs back to your Leera workspace.

It registers with your workspace using a **runner token** (`pm_run_…`), polls for queued
jobs, runs each recorded script and uploads the evidence. Nothing listens for incoming
connections: the runner only makes outgoing HTTPS requests to your server.

It runs **web** tests in Chromium, **Android** tests on emulators and USB phones, **iOS** tests
on simulators and iPhones (Mac only), and desktop apps built with **Electron**, **Tauri**, or
native **Windows** and **macOS** toolkits. Mobile and native desktop drivers use Appium, bundled
with the installers. See [test runners](https://github.com/leera-app/leera-qa-runner/blob/main/docs/test-runners.md)
for each platform's prerequisites and current limitations.

Full guides: [test runners](https://github.com/leera-app/leera-qa-runner/blob/main/docs/test-runners.md) and
[authoring automated test cases](https://github.com/leera-app/leera-qa-runner/blob/main/docs/qa-automation-authoring.md).

- [Install](#install)
- [Connect and run](#connect-and-run)
- [Run in the background](#run-in-the-background)
- [Check the machine: doctor](#check-the-machine-doctor)
- [Android](#android)
- [Configuration](#configuration)
- [Commands and exit codes](#commands-and-exit-codes)
- [Docker](#docker)
- [Uninstall](#uninstall)

## Install

Every installer bundles its own Node.js; you do not need Node installed. Downloads are
listed on the [releases page](https://github.com/leera-app/leera-qa-runner/releases) with a
`SHA256SUMS` file, and the install scripts verify it.

### macOS (Apple silicon and Intel)

```sh
curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh | sh
```

or download `leera-qa-runner-macos-arm64.pkg` (Apple silicon) / `leera-qa-runner-macos-x64.pkg`
(Intel) and open it. The package installs to `/usr/local/lib/leera-qa-runner/<version>` and
links `/usr/local/bin/leera-qa-runner`.

### Linux (x64 and arm64)

```sh
curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh | sh
```

No root needed: it installs under `~/.local/lib/leera-qa-runner/<version>` and links
`~/.local/bin/leera-qa-runner` (change with `--prefix DIR`). Make sure `~/.local/bin` is on
your `PATH`. Chromium needs some system libraries; if a job cannot launch the browser, run the
`sudo … install-deps chromium` command that `leera-qa-runner setup browsers` prints.

Manual install: download `leera-qa-runner-linux-<arch>.tar.gz`, extract it anywhere and run
`leera-qa-runner-linux-<arch>/bin/leera-qa-runner`.

### Windows (x64)

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.ps1 | iex
```

or download and run `leera-qa-runner-windows-x64.exe`. It installs for the current user
(no administrator rights) into `%LOCALAPPDATA%\Programs\leera-qa-runner` and adds it to your
`PATH`; open a new terminal afterwards. The installer is not code-signed yet, so Windows
SmartScreen may warn before it runs ("More info" → "Run anyway").

### npm

With Node.js 22.12 or newer:

```sh
npm install -g @leera/qa-runner
leera-qa-runner setup browsers
```

Appium and the UiAutomator2 driver are optional dependencies: installing with
`--omit=optional` gives a web-only runner.

### Install options

`install.sh` accepts `--version X`, `--prefix DIR` (Linux), `--url URL`, `--token TOKEN`,
`--name NAME`, `--service`, `--no-browsers` and `--base-url URL` (a mirror of the release
assets). `install.ps1` accepts `-Version`, `-Url`, `-Token`, `-Name`, `-Service`,
`-NoBrowsers`, `-Portable` (unpack the `.zip` instead of running the installer) and `-BaseUrl`. Prefer passing the token through the `RUNNER_TOKEN`
environment variable so it does not land in your shell history:

```sh
curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh \
  | RUNNER_TOKEN=pm_run_… sh -s -- --url https://app.example.com --service
```

## Connect and run

1. In your workspace, open **Settings → Test runners**, create a runner pool and copy a
   runner token.
2. Install Chromium (the installers do this for you):

   ```sh
   leera-qa-runner setup browsers
   ```

3. Connect. The token is asked for without echo:

   ```sh
   leera-qa-runner connect --url https://app.example.com --name lab-mac
   ```

   In scripts, pipe it instead: `printf '%s' "$TOKEN" | leera-qa-runner connect --url … --token-stdin`.
   `connect` stores the URL in `~/.leera-qa-runner/config.json`, the token in
   `~/.leera-qa-runner/token` (readable only by you) and runs `doctor`.

4. Run it in this terminal:

   ```sh
   leera-qa-runner start
   ```

   or [install the background service](#run-in-the-background). The runner appears on the
   Test runners page with its OS, architecture and version; queue an automated run and
   watch it pick up the job. Press Ctrl-C to stop after the current step.

`start` options: `--once` (exit after one job), `--headed` (show the browser),
`--labels a,b` (exact label list), `--concurrency N` (browser jobs at once) and
`--run-id N` (only take jobs from one test run).

## Run in the background

```sh
leera-qa-runner service install     # install and start; starts again at login
leera-qa-runner service status
leera-qa-runner service logs -f
leera-qa-runner service restart
leera-qa-runner service stop
leera-qa-runner service start
leera-qa-runner service uninstall
```

The service runs as **your user, in your login session**, so it can open browsers and
Android emulators (and, later, simulators and app windows):

| OS | What is installed |
|---|---|
| macOS | LaunchAgent `~/Library/LaunchAgents/io.leera.qa-runner.plist` (starts at login, restarted if it exits). Keep the Mac logged in; a locked screen is fine for browser jobs. |
| Windows | Scheduled task `leera-qa-runner`, at logon, in your interactive session, with limited rights; restarted on failure. |
| Linux | systemd user unit `~/.config/systemd/user/leera-qa-runner.service`. `loginctl enable-linger` keeps it running after you log out (may need an administrator). |

Services start without your shell profile, so `service install` saves `PATH` and a few other
variables (`JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `PLAYWRIGHT_BROWSERS_PATH`,
proxy variables) into the configuration's `env`. Re-run `service install` after changing them.

Logs are JSON lines in `~/.leera-qa-runner/logs/runner.log`, rotated at 20 MB with five old
files kept.

## Check the machine: doctor

```sh
leera-qa-runner doctor            # human-readable
leera-qa-runner doctor --json     # for scripts
leera-qa-runner doctor --fix      # fix permissions, install Chromium if missing
leera-qa-runner doctor --platform web
leera-qa-runner doctor --platform android
```

It checks Node.js, the runner home and its permissions, the server URL, the token (asking the
server whether it accepts it, without registering a runner), Chromium, and for Android: Appium,
the SDK, adb, the emulator, build-tools, Java, KVM on Linux and unauthorised phones. It exits `0` when
ready and `4` when something marked `[fail]` needs fixing, with the command that fixes it.

## Android

1. Install the Android SDK (Android Studio, or the command-line tools) and Java 17+, and set
   `ANDROID_HOME` (or `"android": {"sdk_path": "…"}` in `config.json`). On Linux, emulators
   need `/dev/kvm` and your user in the `kvm` group. For a phone, enable USB debugging and accept
   the prompt on the phone.
2. Prepare the runner:

   ```sh
   leera-qa-runner setup android                 # Appium home, SDK check, device list
   leera-qa-runner setup android --install-sdk   # also install SDK packages and create an emulator
   leera-qa-runner doctor --platform android
   ```

   `--install-sdk` uses the SDK's own `sdkmanager`, so the SDK directory must already have
   `platform-tools` and `cmdline-tools/latest`; otherwise it prints how to get them. Re-run
   `service install` afterwards so the service sees `ANDROID_HOME` and `JAVA_HOME`.

3. Upload an `.apk` on the **App builds** page (app bundles, `.aab`, are refused), set the
   package id and build on the test environment's **Apps**, create a run with platform
   *Android* and queue it on this runner's pool.

The runner advertises phones (`android`, `android-real`), running emulators and emulators that
exist but are off (`android`, `android-emulator`); an emulator is booted when a job needs it and
stays booted. Each job installs the build, clears the app's data, records an MP4 when asked
(runs over 3 minutes need `ffmpeg` on `PATH`) and captures the app's logcat warnings, errors and
crashes per step. The same devices serve **device sessions**, in which an AI agent explores the
app over MCP before writing a script. Details: [Android](https://github.com/leera-app/leera-qa-runner/blob/main/docs/test-runners.md#android),
[device sessions](https://github.com/leera-app/leera-qa-runner/blob/main/docs/qa-automation-authoring.md#device-sessions).

## Configuration

Settings are read in this order; the first one set wins:

1. command-line flags
2. `RUNNER_*` environment variables
3. legacy `LEERA_URL` / `LEERA_RUNNER_TOKEN`
4. `~/.leera-qa-runner/config.json` (and the `token` file)
5. defaults

```sh
leera-qa-runner config list
leera-qa-runner config get url
leera-qa-runner config set concurrency.web 2
leera-qa-runner config unset proxy
leera-qa-runner config set-token        # replace the token (prompted, or --token-stdin)
leera-qa-runner config path
```

| Config key | Environment variable | Default | Meaning |
|---|---|---|---|
| `url` | `RUNNER_URL` (`LEERA_URL`) | — | Your workspace server, e.g. `https://app.example.com` |
| token (`config set-token`) | `RUNNER_TOKEN` (`LEERA_RUNNER_TOKEN`) | — | Runner pool token, `pm_run_…` |
| `name` | `RUNNER_NAME` | host name | Name shown on the Test runners page |
| `labels.extra` | — | — | Labels added to the detected ones (comma separated) |
| `labels.exclude` | — | — | Detected labels to leave out |
| — | `RUNNER_LABELS` | detected | Exact label list; replaces detection (`--labels` too) |
| `concurrency.web` | `RUNNER_CONCURRENCY` | `1` | Browser jobs at once (`--concurrency`) |
| `headless` | `RUNNER_HEADLESS` | `true` | Run Chromium without a window (`--headed` overrides) |
| `proxy` | `RUNNER_PROXY` | — | Proxy server for the browser |
| `action_timeout_ms` | `RUNNER_ACTION_TIMEOUT_MS` | `15000` | Time limit per action |
| `job_timeout_ms` | `RUNNER_JOB_TIMEOUT_MS` | `900000` | Time limit per job; later steps are blocked |
| `android.sdk_path` | — (`ANDROID_HOME`) | detected | Android SDK directory, absolute path; wins over `ANDROID_HOME` |
| `builds.allow_local_paths` | `RUNNER_ALLOW_LOCAL_PATHS` | `false` | Install apps from a file path on this machine (install `path`); off: such jobs are blocked |
| — | `RUNNER_ONCE` | `false` | Exit after one job (`--once`) |
| — | `RUNNER_RUN_ID` | — | Only take jobs from this test run (`--run-id`) |
| `env.NAME` | — | — | Variables applied when the service starts |
| — | `LEERA_RUNNER_HOME` | `~/.leera-qa-runner` | Where configuration, token, logs and browsers live |
| — | `PLAYWRIGHT_BROWSERS_PATH` | `~/.leera-qa-runner/browsers` when present | Where Chromium is installed |

Labels route jobs: a run that requires labels only goes to runners that have all of them. The
runner detects `web-chromium` when Chromium is installed, and `android`, `android-emulator` and
`android-real` for its Android devices.

### Files in the runner home

| Path | Contents |
|---|---|
| `config.json` | Settings above (mode 0600) |
| `token` | The runner token (mode 0600; narrowed again if someone widens it) |
| `state.json` | pid, runner id and running jobs, for `service status` |
| `install.json` | How the runner was installed (`method`: pkg, exe, tar, brew, winget), read by `update` |
| `versions/` | Versions installed by `update`; `current` (a symlink, `current.txt` on Windows) names the active one |
| `logs/runner.log` | Service log, JSON lines |
| `browsers/` | Chromium installed by `setup browsers` |
| `appium/` | Appium home with the UiAutomator2 driver, seeded by `setup android` |
| `cache/builds/` | Downloaded app builds by SHA-256 (up to 10 GB) |

## Commands and exit codes

| Command | What it does |
|---|---|
| `start [--once] [--service] [--headed] [--labels a,b] [--concurrency N] [--run-id N]` | Register and run jobs until stopped |
| `connect --url URL [--token-stdin] [--name NAME]` | Save URL and token, then run `doctor` |
| `doctor [--json] [--fix] [--offline] [--platform web\|android]` | Check the machine |
| `setup browsers` | Install Chromium |
| `setup android [--install-sdk] [--image ID] [--avd NAME]` | Prepare Appium and the Android SDK, list devices |
| `service install\|uninstall\|start\|stop\|restart\|status\|logs [-f]` | Background service |
| `config get\|set\|unset\|list\|path\|set-token` | Stored configuration |
| `version [--json]` | Print the version |
| `update [--check] [--version X] [--yes]` | Update the runner; `--check` exits 10 when an update is available |

| Exit code | Meaning |
|---|---|
| 0 | OK |
| 1 | Error |
| 2 | Usage or configuration error (unknown option, missing URL or token) |
| 3 | The server rejected the runner token — create a new one and run `config set-token` |
| 4 | The machine is not ready (`doctor` found a failing check) |
| 5 | The server needs a newer runner version — update the runner |
| 130 | Interrupted (Ctrl-C) |

## Update

```sh
leera-qa-runner update --check   # exit 0: up to date, 10: an update is available
leera-qa-runner update           # asks first; --yes skips the question, --version X picks a version
```

`update` follows the way the runner was installed. Package, installer and tarball installs
download `leera-qa-runner-<os>-<arch>.tar.gz` (`.zip` on Windows) from the release, check it
against the release manifest `releases.json` (its Ed25519 signature is required when the build
carries a release key, and the SHA-256 always), unpack it into `~/.leera-qa-runner/versions/<version>`,
switch `versions/current` to it, keep the two newest versions and restart the background service —
no administrator rights. The installed launcher runs `versions/current` whenever it is newer
than the version it was installed with. npm, Homebrew and winget installs print (or, with
`--yes`, run) their own upgrade command; Docker users pull the new image. `RUNNER_UPDATE_BASE`
points `update` at a mirror of the releases page. A running runner logs once a day when the server
reports a newer version.

## Docker

For servers and CI without a desktop, the web-only image keeps working as before (it cannot
run Android jobs):

```sh
docker run -d --restart unless-stopped \
  -e RUNNER_URL=https://app.example.com \
  -e RUNNER_TOKEN=pm_run_… \
  -e RUNNER_NAME=docker-1 \
  ghcr.io/leera-app/leera-qa-runner:latest
```

It reads the same `RUNNER_*` variables.

## Uninstall

1. `leera-qa-runner service uninstall` (if you installed the service).
2. Remove the program:
   - macOS package: `sudo rm -rf /usr/local/lib/leera-qa-runner /usr/local/bin/leera-qa-runner && sudo pkgutil --forget io.leera.qa-runner`
   - Linux: `rm -rf ~/.local/lib/leera-qa-runner ~/.local/bin/leera-qa-runner`
   - Windows: *Settings → Apps → Leera QA Runner → Uninstall*
   - npm: `npm uninstall -g @leera/qa-runner`
3. Remove its data: `rm -rf ~/.leera-qa-runner` (Windows: `%USERPROFILE%\.leera-qa-runner`).
4. Delete the runner from the Test runners page, or revoke its token.
