# Test runners

A test runner is a small program you run on your own machine. It connects to
your Leera instance, picks up the automated test cases queued in a test run,
replays each case's recorded script, and sends back the result of every step
with screenshots, an optional video and a debug log.

Runners are free and unlimited: they use hardware you already own (a laptop, a
spare Mac mini, a CI machine, a server) and nothing is executed on shared
infrastructure. The scripts they replay are written by your AI coding agent
over MCP — see [qa-automation-authoring.md](qa-automation-authoring.md).

| Platform | Status |
|---|---|
| Web (Chromium) | Available |
| Android (emulators and USB phones) | [Available](#android) |
| iOS (simulators and iPhones, on a Mac) | [Available](#ios) |
| Electron apps (macOS, Windows, Linux) | [Available](#electron) |
| Tauri apps (Windows and Linux; macOS only with a WebDriver plugin build) | [Available](#tauri) |
| Windows apps (WinAppDriver, on Windows) | [Available](#windows-apps) |
| macOS apps (Appium Mac2, on a Mac) | [Available](#macos-apps) |
| Running a test run from CI | [Available](#ci-runners) |

---

## How it works

- **Pools.** Runners belong to a *pool*. When you queue a run you choose the
  pool, and any online runner in it can claim the jobs. Create pools under
  **QA → Test runners** (or **Workspace settings → Test runners**).
- **Tokens.** A runner authenticates with a pool token (`pm_run_…`). The token
  is shown once, when you create it. It lets a runner claim that pool's jobs
  and record their results — nothing else.
- **Outbound only.** The runner opens every connection itself (HTTPS to your
  instance) and long-polls for work. Nothing needs to reach the runner, so it
  works behind NAT, VPNs and corporate firewalls, and it can test sites that are
  only reachable from its own network.
- **Labels.** A runner advertises what it can do as labels (`web-chromium` when
  a Chromium browser is installed; `android`, `android-emulator` and
  `android-real` for its Android devices; `ios`, `ios-simulator` and `ios-real`
  for its iOS devices; `electron` when it can drive Electron apps; `tauri`
  when it can drive Tauri apps; `windows` and `macos` when it can drive native
  Windows or macOS apps). A job is
  only claimed by a runner whose labels cover what the job needs.
- **Platforms and devices.** A test run has a platform (web, Android, iOS,
  Electron, Tauri, Windows or macOS), chosen when the run is created. A runner
  only claims a run's jobs when it has a free device of that platform: its
  browser for web, an emulator or phone for Android, a simulator or iPhone for
  iOS, and the machine itself for Electron, Tauri, Windows and macOS apps.
- **One job at a time** by default; `--concurrency N` runs more web jobs in
  parallel on a machine with the memory for it (each browser context needs
  roughly 500 MB). Android and iOS run one job per device, so a machine with two
  devices runs two jobs at once. Desktop apps (Electron, Tauri, Windows and
  macOS) run on the machine itself, so a runner runs one desktop app job at a
  time, whichever of those platforms it is.

The runner is published three ways, all built from the same code and released
with the same version as the server:

| Install | Best for |
|---|---|
| **Installer** (macOS `.pkg`, Windows `.exe`, Linux `.tar.gz`) with Node bundled | Laptops and dedicated test machines; web, Android, Electron, Tauri, iOS and macOS apps on a Mac, Windows apps on Windows |
| **npm** `@leera/qa-runner` | Machines that already have Node 22.12 or newer, and [CI](#ci-runners); web, Android, Electron, Tauri, iOS and macOS apps on a Mac, Windows apps on Windows |
| **Docker** `ghcr.io/leera-app/leera-qa-runner` | Servers and CI; web tests only |

The **Test runners** page in the app shows each of these with your instance's
URL, the current version and a runner name filled in. The commands below are the
same, with placeholders.

---

## Install

Use the runner version that matches your instance (shown on the Test runners
page). A runner older than the instance usually still works; the instance can
be configured to refuse runners below a minimum version, in which case the
runner exits with code 5 and says so.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh | sh -s -- --version <version>
```

The script picks the Apple Silicon or Intel package, checks it against the
release's `SHA256SUMS`, and installs it. You can also download the package
yourself from the [releases page](https://github.com/leera-app/leera-qa-runner/releases):

- `leera-qa-runner-macos-arm64.pkg` — Apple Silicon
- `leera-qa-runner-macos-x64.pkg` — Intel

The packages are signed with a Developer ID and notarized by Apple. They install
into `/usr/local/lib/leera-qa-runner/<version>` and link `leera-qa-runner` into
`/usr/local/bin`.

With Homebrew, when the Test runners page shows a Homebrew command:

```bash
brew install --cask leera-app/tap/leera-qa-runner
```

The cask installs the same notarized package (Homebrew asks for your password,
as the package installer does), and always installs the latest release rather
than the instance's version.

### Windows

In PowerShell (no administrator rights needed):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.ps1))) -Version <version>
```

Or download `leera-qa-runner-windows-x64.exe` from the releases page. It
installs for the current user into `%LOCALAPPDATA%\Programs\leera-qa-runner`
and adds that folder to your user `PATH` (open a new terminal afterwards).

With winget, when the Test runners page shows a winget command:

```powershell
winget install --id Leera.QARunner
```

It runs the same per-user installer and installs the latest release.

> **The Windows installer is not code-signed yet.** SmartScreen shows "Windows
> protected your PC" the first time you run it. Choose **More info → Run
> anyway**, or verify the download against `SHA256SUMS` first:
> `Get-FileHash .\leera-qa-runner-windows-x64.exe -Algorithm SHA256`.

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.sh | sh -s -- --version <version>
```

The script downloads `leera-qa-runner-linux-x64.tar.gz` or
`leera-qa-runner-linux-arm64.tar.gz`, verifies it and unpacks it; `--prefix`
chooses where. Without `--version` the scripts install the latest release.

Chromium needs a set of system libraries on Linux. After downloading Chromium,
`leera-qa-runner setup browsers` prints the `sudo … install-deps chromium`
command that installs them, rather than running `sudo` itself.

### npm

```bash
npm install -g @leera/qa-runner@<version>
```

Needs Node.js 22.12 or newer. Appium and its UiAutomator2 (Android), XCUITest
(iOS), Mac2 (macOS apps) and Windows (Windows apps) drivers are optional
dependencies of the package: npm installs them unless you pass
`--omit=optional`, in which case the runner runs web, Electron and Tauri jobs
only. Chromium is downloaded
by `leera-qa-runner setup browsers`.

### Docker

```bash
docker run -d --name leera-qa-runner --restart unless-stopped \
  --init --shm-size=1g \
  --add-host=host.docker.internal:host-gateway \
  -e RUNNER_URL="https://leera.example.com" \
  -e RUNNER_TOKEN="pm_run_…" \
  -e RUNNER_NAME="ci-box-1" \
  ghcr.io/leera-app/leera-qa-runner:<version>
```

The image contains Chromium and runs web tests only (it is built without the
Appium dependencies, and an emulator needs the host's KVM and display stack).
The image sets `RUNNER_DOCKER=1`, and a runner with that setting registers only
its browser: it never advertises the `electron`, `tauri`, `windows` or `macos`
labels, so desktop
app jobs are not claimed by Docker runners. `--shm-size` matters:
Chromium renders through `/dev/shm`, and Docker's 64 MB default crashes pages.

A site served on the Docker host is not `localhost` inside the container: use
`http://host.docker.internal:<port>` as the test environment's base URL (the
`--add-host` flag defines that name on Linux, and on Linux the site must listen
on `0.0.0.0`).

Self-hosted instances can also start a runner on the server itself with one
switch: **QA → Test runners → Built-in runner** (web tests only; see the
self-hosting configuration guide).

### Check the install

```bash
leera-qa-runner version
leera-qa-runner setup browsers     # downloads Chromium for the runner
leera-qa-runner setup android      # only for Android testing, see below
leera-qa-runner setup ios          # only for iOS testing on a Mac, see below
leera-qa-runner setup electron     # installs nothing; Electron uses the bundled Playwright
leera-qa-runner setup windows      # only for Windows apps, see below
leera-qa-runner setup macos        # only for macOS apps, see below
leera-qa-runner doctor
```

---

## Connect

Create a pool token under **QA → Test runners → your pool → New token**, then:

```bash
leera-qa-runner connect --url https://leera.example.com --name "mac-mini"
```

`connect` asks for the token at a hidden prompt, so it never appears in your
shell history or in the process list. It then:

1. saves the URL, name and token under `~/.leera-qa-runner/`,
2. runs `doctor` and prints its report (`--skip-doctor` leaves this out),
3. prints the next step: `service install` or `start`.

`connect` exits `0` once the URL and token are saved, even when `doctor` found
problems. Scripts that need to know whether the machine is ready should run
`leera-qa-runner doctor` afterwards and check its exit code.

For scripted setups pipe the token in instead:

```bash
printf '%s' "$RUNNER_TOKEN" | leera-qa-runner connect --url https://leera.example.com --name ci-box-1 --token-stdin
```

`leera-qa-runner config set-token` replaces the stored token later (also at a
hidden prompt).

The install scripts can connect in the same step: `install.sh --version <v>
--url <url> --name <name> [--service]` and `install.ps1 -Version <v> …` run
`connect` (and `service install`) after installing.

---

## Start

Run it in the foreground, for a first try or a one-off session:

```bash
leera-qa-runner start
```

| Flag | Effect |
|---|---|
| `--once` | Exit after one job |
| `--headed` | Show the browser window, the window of an emulator the runner boots, and Simulator.app for a simulator it boots (useful while watching a script replay) |
| `--labels a,b` | Replace the detected labels for this process |
| `--concurrency N` | Run up to N jobs in parallel |
| `--run-id N` | Only take jobs from this test run |
| `--service` | Set by the background service; logs go to the runner home's log file only |

`Ctrl+C` stops after the current step and reports the unfinished job as
interrupted by the runner shutting down; press it again to quit immediately.

---

## Run as a background service

```bash
leera-qa-runner service install     # installs and starts it
leera-qa-runner service status      # service state, runner id, current jobs
leera-qa-runner service logs -f     # follow the log (-n N: start from the last N lines, default 100)
leera-qa-runner service restart
leera-qa-runner service stop | start
leera-qa-runner service uninstall
```

The service runs **as your user, in your login session**, not as a system
daemon. That is deliberate: browsers, Android emulators, USB debugging
authorisations, iOS simulators, the signing keychain, app windows and macOS
privacy permissions all belong to a logged-in user.

| OS | Mechanism |
|---|---|
| macOS | LaunchAgent `~/Library/LaunchAgents/io.leera.qa-runner.plist` (starts at login, restarted if it exits) |
| Windows | Scheduled task that starts at logon and restarts on failure (not a Windows Service: services run in Session 0, which has no desktop) |
| Linux | `systemd --user` unit, with `loginctl enable-linger` so it runs without an open session |

Keep the machine logged in. A locked screen is fine for web tests, Android
emulators and iOS simulators, but **not for desktop app tests**: native macOS
and Windows UI tests need an unlocked desktop (see [macOS apps](#macos-apps)
and [Windows apps](#windows-apps)).

Services start without your shell profile, so `service install` records the
`PATH`, `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
`PLAYWRIGHT_BROWSERS_PATH` and proxy variables it sees into the config file's
`env` section. Re-run `service install` after changing those (for example after
installing the Android SDK).

---

## Configuration

Settings are read in this order, first match wins:

1. command-line flags
2. environment variables (`RUNNER_*`, and the older `LEERA_*` names)
3. `~/.leera-qa-runner/config.json`
4. defaults

```bash
leera-qa-runner config list
leera-qa-runner config get url
leera-qa-runner config set name build-agent-3
leera-qa-runner config unset labels.extra
leera-qa-runner config path          # where the config file is
leera-qa-runner config set-token     # hidden prompt
```

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `RUNNER_URL` | — | Instance URL, e.g. `https://leera.example.com`. Legacy name `LEERA_URL` |
| `RUNNER_TOKEN` | — | Pool token (`pm_run_…`); a CI token for `ci` and `builds upload`. Legacy name `LEERA_RUNNER_TOKEN` |
| `RUNNER_NAME` | host name | How the runner appears on the Test runners page. Keep it stable: it is the runner's identity across restarts |
| `RUNNER_LABELS` | detected | Comma-separated labels. When set, it **replaces** detection exactly (what the Docker image relies on) |
| `RUNNER_HEADLESS` | `true` | `false` shows the browser |
| `RUNNER_ONCE` | `false` | Exit after one job |
| `RUNNER_CONCURRENCY` | `1` | Browser jobs at once |
| `RUNNER_RUN_ID` | — | Only take jobs from this test run |
| `RUNNER_PROXY` | — | HTTP proxy the browser uses to reach the site under test |
| `RUNNER_ACTION_TIMEOUT_MS` | `15000` | Default timeout of a single action |
| `RUNNER_JOB_TIMEOUT_MS` | `900000` | A job still running after this is reported blocked |
| `RUNNER_ALLOW_LOCAL_PATHS` | `false` | Let app installs of type `path` (a desktop app, e.g. an [Electron app at a path](#configure-an-electron-app-on-a-test-environment) on this machine) run (config key `builds.allow_local_paths`); when off such jobs are blocked |
| `RUNNER_IOS_TEAM_ID` | — | Apple Developer Team ID that signs WebDriverAgent for real iOS devices (config key `ios.team_id`) |
| `RUNNER_IOS_WDA_BUNDLE_ID` | — | Bundle id WebDriverAgent is signed under on real devices (`ios.wda_bundle_id`) |
| `RUNNER_IOS_SIGNING_ID` | `Apple Development` | Code signing identity for WebDriverAgent (`ios.signing_id`) |
| `RUNNER_TAURI_DRIVER` | — | Path of the `tauri-driver` executable (config key `tauri.driver_path`) |
| `RUNNER_TAURI_NATIVE_DRIVER` | — | Path of the native WebDriver server `tauri-driver` uses: `msedgedriver.exe` on Windows, `WebKitWebDriver` on Linux (config key `tauri.native_driver_path`) |
| `RUNNER_TAURI_MACOS_PLUGIN` | `false` | `1` on a Mac runner whose Tauri builds embed the WebDriver plugin (config key `tauri.macos_plugin`); see [Tauri on macOS](#tauri-on-macos) |
| `RUNNER_DOCKER` | — | Set to `1` by the Docker image; the runner then registers web only |
| `RUNNER_PROJECT`, `RUNNER_ENVIRONMENT`, `RUNNER_PLATFORM` | — | Defaults for `ci --project`, `--environment` and `--platform` ([CI](ci-integration.md#the-ci-command)) |
| `RUNNER_UPDATE_BASE` | `https://github.com/leera-app/leera-qa-runner/releases` | Where `update` fetches `releases.json` and the update archives; point it at a mirror of the release assets that keeps GitHub's `latest/download/<file>` and `download/v<version>/<file>` layout |
| `LEERA_RUNNER_HOME` | `~/.leera-qa-runner` | Runner home directory |

Without `RUNNER_LABELS`, labels are the detected ones plus `labels.extra`, minus
`labels.exclude` (both lists in `config.json`).

### Files

`~/.leera-qa-runner/` is created with mode `0700`:

| Path | Contents |
|---|---|
| `config.json` (0600) | URL, name, labels, service environment |
| `token` (0600) | The pool token. Permissions are re-checked on every read; on Windows the file's ACL is restricted to your user |
| `state.json` | Process id, runner id, current jobs — read by `service status` |
| `install.json` | How the runner was installed (`method`: `pkg`, `exe`, `tar`, `brew`, `winget` or `docker`, plus version, time and prefix); written by the install scripts and installers, and read by `update`. npm installs have none and are recognised by their path |
| `versions/<version>/`, `versions/current` | Runner versions installed by `update`, and the one in use (a symlink; `current.txt` on Windows). The two newest are kept |
| `logs/` | `runner.log`, JSON lines, rotated at 20 MB × 5 |
| `browsers/` | Chromium downloaded by `setup browsers` (unless `PLAYWRIGHT_BROWSERS_PATH` is set) |
| `appium/` | Appium's home (`APPIUM_HOME`) with the bundled UiAutomator2, XCUITest, Mac2 and Windows drivers, seeded by `setup android` / `setup ios` / `setup macos` / `setup windows` |
| `wda/<driver>-<xcode>/` | WebDriverAgent prebuilt for simulators by `setup ios`, one directory per XCUITest driver and Xcode version (`…-real` for real devices; `<dir>.build.log` is the build log) |
| `cache/builds/` | Downloaded app builds, by SHA-256, at most 10 GB (least recently used first out) |
| `logs/emulator-*.log` | Output of emulators the runner booted |
| `winappdriver/` | The WinAppDriver 1.2.1 installer downloaded by `setup windows` |
| `macos-accessibility-blocked` | Written when macOS refused UI testing; while it exists the Mac advertises no macOS device. Removed by `setup macos` |

Settings for app platforms (`config set KEY VALUE`):

| Key | Meaning |
|---|---|
| `android.sdk_path` | Android SDK directory (absolute path); wins over `ANDROID_HOME` |
| `builds.allow_local_paths` | `true` lets app installs of type `path` (a desktop app at a path on this machine) run (default `false`; `RUNNER_ALLOW_LOCAL_PATHS`) |
| `ios.team_id` | Apple Developer Team ID (10 characters) that signs WebDriverAgent for real iOS devices (`RUNNER_IOS_TEAM_ID`) |
| `ios.wda_bundle_id` | Bundle id to sign WebDriverAgent under, e.g. `com.example.WebDriverAgentRunner` (`RUNNER_IOS_WDA_BUNDLE_ID`) |
| `ios.signing_id` | Code signing identity, default `Apple Development` (`RUNNER_IOS_SIGNING_ID`) |
| `tauri.driver_path` | Absolute path of `tauri-driver` (`RUNNER_TAURI_DRIVER`); otherwise `~/.cargo/bin/tauri-driver`, then `PATH` |
| `tauri.native_driver_path` | Windows: absolute path of the `msedgedriver.exe` that matches the installed WebView2 version. Linux: path of `WebKitWebDriver` when it is not on `PATH` (`RUNNER_TAURI_NATIVE_DRIVER`) |
| `tauri.macos_plugin` | `true` on a Mac whose Tauri builds embed the WebDriver plugin (default `false`; `RUNNER_TAURI_MACOS_PLUGIN`) |

---

## Doctor

```bash
leera-qa-runner doctor
leera-qa-runner doctor --json
leera-qa-runner doctor --fix          # apply the fixes it can make without sudo
leera-qa-runner doctor --platform web
leera-qa-runner doctor --offline      # skip the checks that contact the instance
```

`doctor` checks the runner's own install, that the instance is reachable and
accepts the token and the runner version, and each platform's prerequisites
(for web: a Chromium the runner can launch; for the other platforms see
[Android](#check-with-doctor), [iOS](#check-ios-with-doctor),
[Electron](#check-electron-with-doctor), [Tauri](#check-tauri-with-doctor),
[Windows apps](#check-windows-apps-with-doctor) and
[macOS apps](#check-macos-apps-with-doctor)).
Each failure comes with the command that fixes it. It exits `4` when any check
fails (warnings do not count). `--platform` accepts `web`, `android`, `ios`,
`electron`, `tauri`, `windows` and `macos`; any other value exits `2`.

### Commands in this version

`start`, `connect`, `doctor [--platform web|android|ios|electron|tauri|windows|macos]`,
`setup browsers`, `setup android`, `setup ios`, `setup electron`,
`setup tauri`, `setup windows [--install]`, `setup macos`, `ci`,
`builds upload`, `service install|uninstall|start|stop|restart|status|logs`,
`config get|set|unset|list|path|set-token`, `update [--check] [--version X] [--yes]`
(see [Updating](#updating)) and `version [--json]`. Every command prints its
options with `--help`.

`setup electron` installs nothing (Electron apps run with the Playwright bundled
with the runner) and exits `0`; on Linux without `DISPLAY` it reminds you to
install Xvfb. `setup tauri`, `setup windows` and `setup macos` are described
under [Set up Tauri](#set-up-tauri), [Set up Windows apps](#set-up-windows-apps)
and [Set up macOS apps](#set-up-macos-apps). Not available yet: `setup all`
exits `2` with "not available in this runner version", `doctor --platform
linux` exits `2` with "this runner version cannot run … jobs" (native Linux
apps are not supported), and there is no `devices` command. `setup
android`, `setup ios` and `doctor --platform <platform>` list devices in the
meantime.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | Error |
| 2 | Usage or configuration error |
| 3 | Token rejected |
| 4 | Environment not ready (`doctor`) |
| 5 | The instance refuses this runner version — update the runner |
| 130 | Interrupted |

`update --check` exits `10` when a newer version is available.
`ci` adds codes 10–13 (failed, blocked, timed out, cancelled); see
[CI exit codes](ci-integration.md#exit-codes).

---

## Android

Android tests run on emulators and USB-connected phones through Appium's
UiAutomator2 driver, which is bundled with the installers and the npm package.
Any macOS, Windows or Linux machine with the Android SDK can be an Android
runner; the Docker image cannot.

### Prerequisites

- **Android SDK** with `platform-tools` (adb). Add `emulator` and a system image
  to use emulators, and `build-tools` (UiAutomator2 uses `apksigner` from it).
  Android Studio installs all of these; so does `sdkmanager` from the
  command-line tools.
- **Java 17 or newer**, with `JAVA_HOME` set (UiAutomator2 uses it to check app
  signatures).
- **Where the SDK is.** The runner looks, in order, at `android.sdk_path` in
  `~/.leera-qa-runner/config.json`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and the
  default location (`~/Library/Android/sdk` on macOS,
  `%LOCALAPPDATA%\Android\Sdk` on Windows, `~/Android/Sdk` on Linux). The first
  directory that contains `platform-tools/adb` wins.
- **Linux: KVM.** Emulators need hardware virtualisation: `/dev/kvm` must exist
  and be readable and writable by the runner's user, usually by adding the user
  to the `kvm` group (`sudo usermod -aG kvm $USER`, then log in again).
  **Android emulators in Docker or CI need KVM too**; without it they are too
  slow to be usable. macOS and Windows use their own hypervisors.
- **Real phones:** enable Developer options and **USB debugging**, connect the
  phone, unlock it and accept the "Allow USB debugging" prompt for this
  computer. A phone that has not accepted it shows as *unauthorized*.

### Set up

```bash
leera-qa-runner setup android
```

`setup android`:

1. seeds Appium's home (`~/.leera-qa-runner/appium`) with the bundled
   UiAutomator2 driver and checks that Appium sees it,
2. finds the Android SDK and prints where it came from,
3. lists the devices: connected phones and running emulators, plus every
   emulator (AVD) that exists but is not running.

It exits `4` when something is missing (for example the SDK, or Appium in an npm
install made with `--omit=optional`).

`--install-sdk` installs SDK packages with the SDK's own `sdkmanager`:
`platform-tools`, `emulator`, `build-tools;35.0.0`, `platforms;android-35` and a
system image (default `system-images;android-35;google_apis;arm64-v8a` on Apple
Silicon and other ARM machines, `…;x86_64` otherwise; `--image ID` picks
another). `sdkmanager` asks you to accept the SDK licences. When no emulator
exists yet, it then creates one from that image (`--avd NAME`, default
`leera_pixel`, Pixel 8 profile).

```bash
leera-qa-runner setup android --install-sdk
leera-qa-runner setup android --install-sdk --image "system-images;android-34;google_apis;x86_64" --avd pixel_api34
```

`--install-sdk` needs an SDK directory the runner can find that already has
`platform-tools` and the command-line tools (`cmdline-tools/latest`). When it
has not, the command installs nothing and prints the steps instead: download
"Command line tools only" from developer.android.com, unpack it to
`<sdk>/cmdline-tools/latest`, set `ANDROID_HOME`, and run it again. If you start
from the command-line tools alone, install `platform-tools` with
`sdkmanager --sdk_root=<sdk> platform-tools` once so the runner can find the SDK.

After installing the SDK, re-run `leera-qa-runner service install` so the
background service picks up `ANDROID_HOME` and `JAVA_HOME`.

### Check with doctor

```bash
leera-qa-runner doctor --platform android
```

| Check | Fails / warns when |
|---|---|
| Android: Appium | Appium or the UiAutomator2 driver is not installed with this runner (fail) |
| Android: SDK | No SDK with `platform-tools` was found (fail) |
| Android: adb | `adb version` does not run (fail) |
| Android: emulator | The emulator package is missing; only USB devices can be used (warn) |
| Android: build-tools | No `build-tools` with `apksigner` (warn) |
| Android: Java | No Java found via `JAVA_HOME` or `PATH` (warn) |
| Android: KVM | Linux only: `/dev/kvm` missing or not accessible (warn) |
| Android: devices | A connected phone has not authorised this computer (warn) |

### Devices and labels

The runner advertises every Android device it finds, and re-reads the list while
it runs:

| Device | Advertised as | Labels |
|---|---|---|
| Connected phone | its adb serial, named after the model | `android`, `android-real` |
| Running emulator | its serial (`emulator-5554`), named after the AVD | `android`, `android-emulator` |
| Emulator that is not running | `avd:<name>` | `android`, `android-emulator` |

**Emulators are booted on demand.** When a job or session needs an AVD that is
not running, the runner boots it (headless unless `start --headed`, no audio, no
boot animation, software GPU), waits until Android reports the boot completed,
and prepares it once per boot: animations off, screen kept awake, keyguard
dismissed. Emulators stay booted between jobs; their output goes to
`~/.leera-qa-runner/logs/emulator-<id>.log`. Real phones get the same
preparation where the phone allows it (some refuse to change settings; that is
logged and ignored).

When you queue a run you can leave the device as *Any Android device*, pick a
specific device on a specific runner, or require labels, e.g. `android-real` to
run only on phones.

### App builds

The app under test comes from the run's test environment (below). To test a
build rather than an app you installed yourself, upload it to the project:

- **In the app:** **QA → App builds → Upload build**. The upload shows progress
  and the size limit (500 MB by default on self-hosted instances; see
  `QA_BUILD_MAX_MB`).
- **From a script or CI:** the App builds page has an **Upload from CI** snippet
  with your instance's URL and project filled in. It registers the build, uploads
  the file to storage with the returned link, and marks it ready:

  ```bash
  RESPONSE=$(curl -fsS -X POST "$BASE_URL/api/v1/qa-app-builds/" \
    -H "Authorization: jwt $TOKEN" -H "Content-Type: application/json" \
    -d "{\"project\": 12, \"platform\": \"android\", \"file_name\": \"app-release.apk\", \"size_bytes\": $(wc -c < app-release.apk), \"sha256\": \"$(shasum -a 256 app-release.apk | cut -d' ' -f1)\", \"version_name\": \"1.2.0\"}")
  BUILD_ID=$(echo "$RESPONSE" | jq -r '.data.build.id')
  UPLOAD_URL=$(echo "$RESPONSE" | jq -r '.data.upload.url')
  curl -fsS -X PUT --upload-file app-release.apk "$UPLOAD_URL"
  curl -fsS -X POST "$BASE_URL/api/v1/qa-app-builds/$BUILD_ID/finish/" -H "Authorization: jwt $TOKEN"
  ```

  A pipeline can use `leera-qa-runner builds upload` with a CI token instead
  ([CI integration](ci-integration.md#builds-upload)).

  When storage cannot be reached directly, send the file to
  `POST /api/v1/qa-app-builds/<id>/content/` as multipart form data instead
  (up to 100 MB by default, `QA_BUILD_RELAY_MAX_MB`); the app does this on its
  own when the direct upload fails.

Android builds must be **`.apk`** files. **App bundles (`.aab`) are refused**:
a bundle cannot be installed on a device without the signing keys, so upload a
universal APK (for example from `bundletool build-apks --mode=universal`, or
your build's APK output). The runner downloads a build with a link that expires
after 15 minutes, checks its SHA-256, and keeps it in
`~/.leera-qa-runner/cache/builds` so the next job on that runner skips the
download.

A project keeps up to 100 builds per platform. Builds older than 30 days are
cleaned up, except the newest 20, pinned builds, environments' default builds
and builds a queued or running job uses (such a build cannot be deleted by hand
either).

### Configure the app on a test environment

A test environment says which app to open for each platform. Under **QA →
Environments → your environment → Apps**, add an Android app:

| Field | Meaning |
|---|---|
| Package ID | The application id, e.g. `com.example.app`. Also available to scripts as `{{app.id}}` |
| Launch activity | Optional, e.g. `.MainActivity`. Empty opens the app's default launcher activity |
| App source | **Build**: install an uploaded build — the environment's default build, or *Latest upload*. **Already installed on the runner**: install nothing; the app must already be on every device that may run the job |

An environment's base URL is only required for web runs; for Android, set it
when scripts use `{{env.base_url}}` (for example in deep links).

When a run is queued you can pick a different build for that run; otherwise
the environment's default build, or else the newest ready build, is used.

### What a job does on the device

1. Leases the device (boots the emulator if needed); nothing else uses it until
   the job ends.
2. Installs the build (`adb install -r -t -g`: replace, allow test builds, grant
   runtime permissions), or checks that an already-installed app is there.
3. Starts an Appium session on the device and **clears the app's data**
   (`clearApp`), so every job starts from a fresh install state.
4. Starts screen recording (when the run asked for video) and logcat capture,
   then launches the app (the launch activity, or the default one).
5. Runs the steps. After the job it stops the app, **uninstalls it when the job
   installed it from a build**, and releases the device.

### Video and logs

- **Video** is recorded on the device as **MP4** and attached to the case like
  web videos. Android records in 3-minute chunks: a case that runs longer than 3
  minutes needs **`ffmpeg` on the runner's `PATH`** to join them, otherwise the
  video cannot be saved (the results are still recorded). Recording stops at 30
  minutes.
- **Device log.** The runner follows `logcat` while the job runs and keeps the
  app's warning and error lines (at most 200 per step) under the step that was
  running, plus **crash reports** (`FATAL EXCEPTION` blocks and `ANR in` lines
  for the app). The run page shows them in each step's debug log. Credential
  values are redacted.

---

## iOS

iOS tests run on simulators and connected iPhones and iPads through Appium's
XCUITest driver, which is bundled with the installers and the npm package. **An
iOS runner is a Mac with Xcode**; Windows, Linux and the Docker image cannot run
iOS jobs.

### iOS prerequisites

- **Full Xcode**, not only the Command Line Tools: install Xcode from the App
  Store, open it once so it installs its components and you accept its licence,
  and point the developer directory at it:

  ```bash
  sudo xcode-select -s /Applications/Xcode.app
  xcode-select -p        # must print …/Xcode.app/Contents/Developer, not …/CommandLineTools
  ```

- **At least one simulator runtime** (Xcode → Settings → Components) for
  simulator tests. Simulators themselves are listed in Xcode → Window → Devices
  and Simulators.
- **Real devices** additionally need:
  - **Developer Mode** turned on on the device (Settings → Privacy & Security →
    Developer Mode, then restart it),
  - the device **paired** with this Mac: connect it with a cable, unlock it and
    tap **Trust** (afterwards it can also be reached over the same network),
  - **your Apple Developer team** to sign WebDriverAgent (the test agent Appium
    installs on the device) — set `ios.team_id`, see [Real devices](#real-ios-devices),
  - and an app build **signed for that team** with a provisioning profile that
    includes the device.

### Set up iOS

```bash
leera-qa-runner setup ios
```

`setup ios`:

1. checks that full Xcode is selected and `xcodebuild` runs, and prints its
   version,
2. seeds Appium's home (`~/.leera-qa-runner/appium`) with the bundled XCUITest
   driver and checks that Appium sees it,
3. **prebuilds WebDriverAgent for simulators** into
   `~/.leera-qa-runner/wda/<xcuitest-driver-version>-<xcode-version>` (several
   minutes the first time; the build log is written next to it as
   `<dir>.build.log`). Jobs then start WebDriverAgent from this build instead of
   compiling it. A later run skips the build while the driver and Xcode versions
   stay the same; `--rebuild` builds it again,
4. lists simulators and connected devices, says why a real device is not ready,
   and reminds you to set a Team ID when a real device is connected.

It exits `4` when something is missing, and on any computer that is not a Mac.
Without the prebuild, the first simulator job builds WebDriverAgent itself,
which can take longer than a job is allowed to wait. After an Xcode update, run
`setup ios` again. In CI, cache the `wda/` directory keyed on both versions (the
[iOS template](ci-integration.md#github-actions-ios) does).

### Check iOS with doctor

```bash
leera-qa-runner doctor --platform ios
```

| Check | Fails / warns when |
|---|---|
| iOS: host | Not a Mac (warn; iOS is skipped) |
| iOS: Xcode | Xcode is missing, `xcodebuild` does not run, or `xcode-select` points at the Command Line Tools (fail) |
| iOS: Appium | The XCUITest driver is not installed with this runner (fail) |
| iOS: WebDriverAgent | Not prebuilt for this driver and Xcode version; the first simulator job builds it (warn) |
| iOS: simulators | No iOS simulator exists (warn) |
| iOS: real devices | A connected device is not paired, has Developer Mode off, or is not reachable (warn) |
| iOS: signing | A real device is connected but no valid `ios.team_id` is set (warn) |

### iOS devices and labels

| Device | Advertised as | Labels |
|---|---|---|
| Simulator (booted or shut down) | its UDID, named after the simulator, with the iOS version | `ios`, `ios-simulator` |
| Connected iPhone or iPad (offline devices are not offered) | its UDID, named after the device | `ios`, `ios-real` |

**Simulators are booted on demand.** When a job or session needs a simulator
that is not running, the runner boots it headless (`--headed` also opens
Simulator.app), waits until the boot completes, and prepares it once per boot:
keyboard autocorrection and predictions off, and the one-time keyboard
introduction marked as seen, so typing is predictable. A simulator the runner
booted for a job is shut down again when the job ends; one that was already
running stays running.

When you queue a run you can leave the device as *Any iOS device*, pick a
specific device on a specific runner, or require labels, e.g. `ios-real` to run
only on physical devices.

### Real iOS devices

WebDriverAgent must be signed by your Apple Developer team before it can run on
a device. Configure the signing once per Mac:

```bash
leera-qa-runner config set ios.team_id ABCDE12345
leera-qa-runner config set ios.wda_bundle_id com.example.WebDriverAgentRunner   # optional
leera-qa-runner config set ios.signing_id "Apple Development"                    # optional, the default
```

or set `RUNNER_IOS_TEAM_ID`, `RUNNER_IOS_WDA_BUNDLE_ID` and
`RUNNER_IOS_SIGNING_ID` (the environment wins over the config file).

| Key | Meaning |
|---|---|
| `ios.team_id` | Your 10-character Apple Developer Team ID (Xcode → Settings → Accounts, or developer.apple.com → Membership). Required for real devices: a job on a real device without it is blocked |
| `ios.wda_bundle_id` | The bundle id WebDriverAgent is signed under. Set it when your team cannot use the default one, e.g. with a free account or an explicit App ID |
| `ios.signing_id` | The code signing identity in your keychain; default `Apple Development` |

The signing identity must be in the keychain of the user the runner runs as
(the background service runs in your login session, so it uses your keychain).
WebDriverAgent is built and signed for real devices by the first job on a device
(into `wda/<driver>-<xcode>-real`), which takes several minutes. The first time,
the device may ask you to trust the developer (Settings → General → VPN & Device
Management).

**The app under test must be signed for your team** too: an `.ipa` exported with
a development or ad hoc profile that includes the device's UDID. An App Store
build cannot be installed.

### iOS app builds

Upload builds on **QA → App builds** (or with
[`builds upload`](ci-integration.md#builds-upload) from CI), as for Android. What
an iOS job can install depends on the device:

| Device | Build | Refused with |
|---|---|---|
| Real device | **`.ipa`** signed for your team | `this build is a simulator .app; real devices need an .ipa signed for your team` |
| Simulator | **a zipped `.app` built for the simulator** (`xcodebuild … -sdk iphonesimulator`, then zip the `.app` folder) | `this build is an .ipa; simulators need a zipped .app built with -sdk iphonesimulator` |

A job with the wrong kind of build is reported **blocked** with that message
before any device is booted; a zipped `.app` that turns out to be built for
devices is refused the same way. To build one for simulators:

```bash
xcodebuild build -scheme MyApp -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO
cd build/Build/Products/Debug-iphonesimulator && zip -qry ~/MyApp.zip MyApp.app
```

On a test environment, add an iOS app with its **Bundle ID** (e.g.
`com.example.app`, available to scripts as `{{app.id}}`) and the app source:
**Build** or **Already installed on the runner**. iOS apps have no launch
activity.

### What an iOS job does

1. Leases the device (boots the simulator if needed), and refuses a build of the
   wrong kind.
2. Downloads the build (checked by SHA-256 and cached like Android builds) and
   unpacks a zipped `.app`.
3. Starts an Appium session with WebDriverAgent (the prebuilt one on
   simulators).
4. Stops the app, **uninstalls it and installs the build again**, so every job
   starts from a fresh install. With *Already installed on the runner*, it only
   checks that the app is there.
5. Starts the device log and, when the run asked for video, screen recording,
   then launches the app.
6. Runs the steps. Afterwards it stops the app, **uninstalls it when the job
   installed it from a build**, and releases the device.

`reset {}` in a script reinstalls the build; for an app that is already
installed it clears the app's data on simulators and is blocked on real
devices.

### iOS video and logs

- **Video** is H.264 video (in a QuickTime container with some Xcode versions;
  it plays in Chrome and Safari). On simulators it is recorded with `simctl` and
  needs nothing else. On real devices Appium records the screen, which needs
  **`ffmpeg` on the Mac's `PATH`**; without it the job runs without a video.
  Recording stops at 30 minutes.
- **Device log.** On simulators the runner follows the simulator's system log
  for the app's process; on real devices it reads the device's syslog through
  Appium. The app's error and fault lines (at most 200 per step) are kept under
  the step that was running, and on simulators so are **crash reports** of the
  app. The run page shows them in each step's debug log, with credential values
  redacted.

---

## Electron

Electron apps are driven with Playwright, which is part of every runner install:
the runner starts the app's executable and works with its windows the way it
works with a web page. Electron jobs run on **macOS, Windows and Linux**
runners installed with an installer or npm. The Docker image runs web jobs
only: it does not advertise the `electron` label (see [Docker](#docker)).

### Electron prerequisites

- **A build of the app for the runner's operating system**: an uploaded build
  or the app installed on the runner (see [Electron app builds](#electron-app-builds)).
  A macOS build runs on Mac runners only, a Windows build on Windows runners, a
  Linux build on Linux runners.
- **A display.** On macOS and Windows, run the runner in a logged-in desktop
  session. On **Linux without a display** (no `DISPLAY`, as on most servers and
  CI machines), install Xvfb and the runner starts a virtual display (`Xvfb
  :99`) for each job:

  ```bash
  sudo apt-get install -y xvfb      # Debian and Ubuntu
  ```

- **The system libraries your Electron app needs** on Linux (for example
  `libnss3`, `libgbm1`, `libgtk-3-0` and ALSA). If the app starts on the machine
  by hand, the runner can start it too. Linux runners also need `unzip` for
  `.zip` builds (macOS uses `ditto`, Windows the built-in `tar`).

### Check Electron with doctor

```bash
leera-qa-runner doctor --platform electron
```

`doctor` checks that the runner can drive Electron apps and, on Linux, warns
when there is neither a display nor Xvfb.

### Electron devices and labels

A runner that can drive Electron apps advertises the machine itself as one
device:

| Device | Advertised as | Labels |
|---|---|---|
| This machine | id `host`, named after the machine, with the OS version | `electron` |

**One desktop app job at a time** per runner (Electron, Tauri, Windows or macOS app): the app's windows share one desktop.
When you queue a run you can leave the device open or pick a specific runner's
machine, which also fixes the operating system. To keep builds for one
operating system on matching runners, give each operating system its own pool.

### Electron app builds

Upload builds on **QA → App builds** with the platform *Electron* (or with
[`builds upload --platform electron`](ci-integration.md#builds-upload) from CI).
The runner reads the file's extension to unpack it:

| File | Contains | Runs on |
|---|---|---|
| **`.zip`** | The packaged app directory, or a `.app` bundle | macOS, Windows, Linux |
| **`.AppImage`** | The Linux AppImage | Linux |
| **`.exe`** | A portable Windows executable (not an installer) | Windows |
| **`.dmg`** | A disk image with the `.app` bundle | macOS |

The runner downloads the build, checks its SHA-256 and caches it like other
builds, unpacks it into a private temporary folder (deleted after the job), and
on macOS removes the quarantine mark from your own build so the system does not
stop it. A download whose SHA-256 differs from the build's is refused ("the
downloaded build's sha256 … does not match …"); the job is retried and the case
ends up blocked. It then **finds the executable**:

| OS | The executable is |
|---|---|
| macOS | `<name>.app/Contents/MacOS/<executable>`: the one named like the bundle, else the first executable file |
| Windows | The first `.exe` at the top level of the build, skipping `Uninstall*.exe` and `*Update*.exe` |
| Linux | The `.AppImage` itself, or the first executable (ELF) file at the top level of the build, skipping Chromium helpers such as `chrome-sandbox` |

"Top level" also covers **one wrapper folder**: when a zip holds a single
folder (other than a `.app`), the runner looks inside it too, but no deeper.

When the build holds several executables, or the app's executable is in a
subfolder, set **Executable (optional)** on the environment's app (below) to
the executable's path **relative to the unpacked build**, e.g.
`MyApp.app/Contents/MacOS/MyApp` or `bin/my-app`.

### Configure an Electron app on a test environment

Under **QA → Environments → your environment → Apps**, add an Electron app:

| Field | Meaning |
|---|---|
| App ID | Optional and informational, e.g. `com.example.desktop`; available to scripts as `{{app.id}}` |
| Executable (optional) | Path of the executable inside the build, relative to the unpacked build; overrides the detection above |
| App source | **Build**: an uploaded build — the environment's default build, or *Latest upload*. **Installed at path**: the absolute path on the runner machine of the app's executable, its `.app` bundle, or a folder that is searched like an unpacked build (Executable, when set, is then relative to that folder) |

*Already installed on the runner* is not an app source for Electron (such an
environment is refused with "electron apps need an uploaded build or a path on
the runner"). The base URL is optional for Electron; set it when scripts use
`{{env.base_url}}`.

**Apps at a path on the runner** run only when the runner allows it, because
the environment then names a program on that machine:

```bash
leera-qa-runner config set builds.allow_local_paths true    # or RUNNER_ALLOW_LOCAL_PATHS=true
```

Without it, such jobs are blocked. The path must exist on every runner that may
claim the job.

### What an Electron job does

1. Takes the runner's desktop slot (one desktop app job at a time).
2. Downloads, checks and unpacks the build and finds the executable, or checks
   that the path on the runner exists (and is allowed).
3. On Linux without a display, starts Xvfb and points the app at it.
4. Starts the app with Playwright before the first step. When the script's
   first action is `launch {args}`, those `args` are used for this start and
   that `launch` does not start the app a second time; a script that does not
   begin with `launch` still gets the app started, without arguments. Any later
   `launch` closes the running app and starts it again, `terminate {}` closes
   it, and `focus_window {}` picks which window later actions work on.
5. Runs the steps, then closes the app (and anything it started) and stops
   Xvfb if it started one.

What the app gets:

- **Arguments.** The script's `args`, except the switches the runner uses
  itself: `--inspect*`, `--remote-debugging-port`, `--remote-debugging-pipe`
  and `--remote-allow-origins` are refused ("reserved for the runner").
- **Environment.** The runner's environment without `RUNNER_TOKEN`,
  `LEERA_RUNNER_TOKEN`, `NODE_OPTIONS` and `ELECTRON_RUN_AS_NODE` (plus
  `DISPLAY` when the runner started Xvfb). Everything else the runner was
  started with reaches the app, so do not keep other secrets there.
- **Its own data folder, unchanged.** The runner does not give the app a fresh
  profile: its `userData` (settings, local storage, caches) carries over
  between jobs and sessions on the same machine. To start clean, have the app
  take a data-directory argument and pass a unique one with `launch` (see
  [Electron app state](qa-automation-authoring.md#electron-app-state-and-builds)).
- **Fallback launch.** When Playwright cannot start the app (for example an app
  whose Electron fuses disable the Node.js inspector), the runner starts it
  once more with a DevTools port on `127.0.0.1` and connects to that. The job
  runs the same, but **without video**.

### Electron video and logs

- **Video** is WebM, recorded from the app's window as for web runs. It needs
  nothing else, but it is not recorded when the app had to be started with the
  DevTools-port fallback above. A runner that only offers Electron still
  advertises WebM video and step debug logs.
- **Debug log.** As for web runs: the focused window's console errors and
  warnings, page errors and network requests, per step, with credential values
  redacted.

---

## Tauri

Tauri apps are driven through WebDriver: the runner starts
[`tauri-driver`](https://crates.io/crates/tauri-driver) **2.0.6**, which starts
the app and hands its web view to the operating system's native WebDriver
server. That native server exists on **Linux** (`WebKitWebDriver`, for
WebKitGTK) and **Windows** (`msedgedriver`, for WebView2) only. **macOS has no
WebDriver for its web view**, so a plain Tauri build cannot be tested on a Mac;
see [Tauri on macOS](#tauri-on-macos).

The Docker image does not run Tauri jobs (see [Docker](#docker)). Use a runner
installed with an installer or npm.

### Tauri prerequisites

**Linux** (Debian and Ubuntu shown):

```bash
# WebKitWebDriver, and Xvfb for machines without a display
sudo apt-get install -y webkit2gtk-driver xvfb

# tauri-driver, with Rust's cargo (https://rustup.rs)
cargo install tauri-driver --version 2.0.6 --locked
```

- **The WebKitGTK runtime your app needs** (`libwebkit2gtk-4.1-0` for Tauri 2).
  If the app starts on the machine by hand, the runner can start it too.
- **A display.** On a machine without one (no `DISPLAY`), install Xvfb and the
  runner starts a virtual display for the job, as for Electron.
- `unzip` for `.zip` builds.

**Windows:**

- **tauri-driver**: `cargo install tauri-driver --version 2.0.6 --locked`.
- **msedgedriver of the same version as the WebView2 runtime** on the machine.
  WebView2 updates itself with Microsoft Edge, and a driver whose version does
  not match cannot start a session. Check the installed version (*Settings →
  Apps → Installed apps → Microsoft Edge WebView2 Runtime*), download the
  matching `msedgedriver` from Microsoft, and tell the runner where it is:

  ```powershell
  leera-qa-runner config set tauri.native_driver_path "C:\tools\msedgedriver.exe"
  ```

  Replace the driver whenever WebView2 updates; `doctor --platform tauri` is
  the place to check after an update.
- **A logged-in desktop session**, as for Electron.

On both, the runner finds `tauri-driver` at `tauri.driver_path` (or
`RUNNER_TAURI_DRIVER`), then `~/.cargo/bin/tauri-driver`, then on `PATH`. The
background service may not see your shell's `PATH`: set `tauri.driver_path`
when the terminal works and the service does not.

### Set up Tauri

```bash
leera-qa-runner setup tauri
```

`setup tauri` does not install system packages or Rust. It looks for
`tauri-driver` and the native WebDriver server, prints where it found each and
the commands above for what is missing, and on Linux without a display reminds
you to install Xvfb. It exits `0` when Tauri is ready and `4` while something is
missing, so run it again after installing. On macOS it explains the
[plugin requirement](#tauri-on-macos) and exits `4` until `tauri.macos_plugin`
is on.

### Check Tauri with doctor

```bash
leera-qa-runner doctor --platform tauri
```

`doctor` checks `tauri-driver`, `WebKitWebDriver` (Linux) or the configured
`msedgedriver` (Windows), and on Linux reports the display: an existing
`DISPLAY`, Xvfb the jobs will start, or a warning when there is neither. On
macOS it fails until `tauri.macos_plugin` is on. A plain `doctor` (without
`--platform`) lists the Tauri checks only on a runner that can already run
Tauri jobs, so a machine without `tauri-driver` is not reported as broken;
ask with `--platform tauri`.

### Tauri devices and labels

| Device | Advertised as | Labels |
|---|---|---|
| This machine | id `host`, named after the machine, with the OS version | `tauri` |

The machine is advertised only when the runner can actually drive Tauri apps:

- **Linux and Windows**: when both `tauri-driver` and the native WebDriver
  server are found.
- **macOS**: only when `tauri.macos_plugin` is `true`.
- **Docker** (`RUNNER_DOCKER=1`): never.

A runner that does not advertise the device never claims Tauri jobs; they stay
queued for another runner. **One desktop app job at a time** per runner: a
Tauri job waits while the same runner runs an Electron job, and the reverse. As with
Electron, a build runs only on the operating system it was built for: give
each operating system its own pool, or pick a specific runner's machine when
you queue the run.

### Tauri app builds

Upload builds on **QA → App builds** with the platform *Tauri* (or with
[`builds upload --platform tauri`](ci-integration.md#builds-upload)):

| File | Contains | Runs on |
|---|---|---|
| **`.zip`** | The app folder (the executable and anything next to it), or a `.app` bundle | Linux, Windows, macOS (plugin builds) |
| **`.AppImage`** | The Linux AppImage | Linux |
| **`.exe`** | The app's portable executable, e.g. `target/release/my-app.exe` (not the NSIS setup program) | Windows |
| **`.dmg`** | A disk image with the `.app` bundle | macOS, plugin builds only |

Installers and packages are refused, because they cannot run in place: an
`.msi` with "an .msi installer cannot run in place — upload the portable .exe
or a zip of the installed app folder", a `.deb` with "a .deb package cannot run
in place — upload the .AppImage or a zip of the installed app folder". Downloading, checking,
caching and unpacking work as for [Electron builds](#electron-app-builds), and
so does finding the executable, including **Executable (optional)** on the
environment's app to point at it explicitly.

Configure the app on a test environment as for
[Electron](#configure-an-electron-app-on-a-test-environment): App ID
(optional), Executable (optional), and App source **Build** or **Installed at
path** (which needs `builds.allow_local_paths`). *Already installed on the
runner* is refused with "tauri apps need an uploaded build or a path on the
runner".

### What a Tauri job does

1. Takes the runner's desktop slot (one desktop app job at a time).
2. Downloads, checks and unpacks the build and finds the executable, or checks
   that the path on the runner exists (and is allowed).
3. On Linux without a display, starts Xvfb on `:99` (or uses the one already
   running there).
4. Starts `tauri-driver` with the native WebDriver server and opens a WebDriver
   session for the app's executable, which starts the app. On macOS it starts
   the app itself (see below). A script's `launch`, `terminate` and
   `focus_window` behave as for [Electron](#what-an-electron-job-does).
5. Runs the steps, then ends the session, closes the app and stops
   `tauri-driver` and Xvfb.

Locating elements and taking snapshots is done by two scripts that ship with
the runner, run in the app's web view through WebDriver. They are the only
scripts the runner executes there; a test script cannot run JavaScript of its
own. Targets are therefore limited to `css`, `text`, `test_id` and `xpath` (see
[Tauri actions](qa-automation-authoring.md#tauri-actions)).

### Tauri on macOS

A Mac can run Tauri jobs only for builds that **embed a WebDriver server in the
app**, through the `tauri-plugin-wdio-webdriver` plugin. Such a build must be a
test build:

- Register the plugin only in a debug build or behind a Cargo feature you
  enable for test builds. **Never ship it in a production build**: it lets any
  local program drive the app.
- Upload that build (a zipped `.app` or a `.dmg`) for the environment the Mac
  runs.

Then turn the plugin mode on for the Mac runner and restart it:

```bash
leera-qa-runner config set tauri.macos_plugin true    # or RUNNER_TAURI_MACOS_PLUGIN=1
```

With the setting on, the runner advertises its `tauri` device and, for each job,
starts the app with `TAURI_WEBDRIVER_PORT` set to a free local port and waits up
to 30 seconds for `http://127.0.0.1:<port>/status`. When nothing answers, the
job is reported **blocked** with:

> Tauri on macOS needs a build with the embedded WebDriver plugin

Without the setting, a Mac runner never claims Tauri jobs.

### Tauri video and logs

- **No video.** Tauri runs record no video, whatever the run's video setting.
- **Screenshots** for steps (verified and failure screenshots, `screenshot`
  actions) are taken through WebDriver.

### Tauri known limitations

- **macOS:** only builds with the embedded WebDriver plugin, and only with
  `tauri.macos_plugin` on.
- **Windows:** `msedgedriver` must match the WebView2 version, and WebView2
  updates on its own; update `tauri.native_driver_path` with it.
- **Targets** are `css`, `text`, `test_id` and `xpath` only; no `role`,
  `label` or `placeholder`. Add `data-testid` attributes to the elements tests
  use.
- **No video.**
- **Native parts of the app** outside the web view (system menus, native file
  dialogs, notifications, the tray) cannot be reached.
- **Not in Docker:** the Docker image runs web jobs only.
- **One desktop app job at a time** per runner, shared with Electron and
  native Windows and macOS apps.

---

## Windows apps

Native Windows apps (Win32, WPF, WinForms, UWP and WinUI) are driven through
Windows UI Automation: the runner starts Appium with its Windows driver, which
talks to Microsoft's **WinAppDriver 1.2.1**. Windows app jobs run on **Windows
runners** installed with the installer or npm, in a logged-in desktop session.

### Windows prerequisites

- **WinAppDriver 1.2.1.** `setup windows` downloads the installer for you
  (below). Other WinAppDriver versions are not supported.
- **Developer Mode on**: *Settings → System → For developers → Developer Mode*
  (*Settings → Privacy & security → For developers* on older Windows 11
  builds). WinAppDriver refuses to start without it.
- **An interactive desktop session.** UI Automation needs a real, visible
  desktop:
  - Run the runner in a terminal of the logged-in user, or install it with
    `leera-qa-runner service install`, which creates a **scheduled task that
    starts at logon** in that user's session. Do not wrap the runner in a
    Windows Service (or use `sc create`/NSSM): services run in Session 0,
    which has no desktop, and every job fails.
  - Keep the session unlocked and on screen. A locked screen, a screen saver,
    or a **minimised or disconnected Remote Desktop window** stops the desktop
    from rendering, and actions then fail or time out. On a dedicated test
    machine turn off the screen lock and use automatic sign-in.
- **A build of the app for Windows**, the app installed at a path on the
  runner, or the app installed on the machine (see
  [Windows app builds](#windows-app-builds)).

### Set up Windows apps

```powershell
leera-qa-runner setup windows
```

`setup windows` links the bundled Appium Windows driver into the runner's
Appium home, downloads the WinAppDriver 1.2.1 installer (`.msi`) into the
runner home and checks it against a pinned SHA-256, then prints the command
that installs it and the Developer Mode steps. It does not change system
settings. Run the printed install command, turn Developer Mode on, and run
`setup windows` again until it reports Windows apps as ready.

To let it run the installer too, pass `--install` in an **elevated**
PowerShell (*Run as administrator*); the installer then runs silently:

```powershell
leera-qa-runner setup windows --install
```

From a shell that is not elevated `msiexec` fails, and `setup windows`
prints the error and the command to run as Administrator. Developer Mode is
never switched on by the runner. `setup windows` exits `0` when WinAppDriver
1.2.1 is installed and Developer Mode is on, and `4` otherwise (including
right after downloading the installer without `--install`).

### Check Windows apps with doctor

```powershell
leera-qa-runner doctor --platform windows
```

`doctor` checks that WinAppDriver 1.2.1 is installed, Developer Mode is on and
the Appium Windows driver is installed with the runner, and warns when `ffmpeg`
is missing (no video). It cannot tell whether the runner is in an interactive
desktop session: that shows up as jobs failing at once (see
[Troubleshooting](#troubleshooting)). Each failure names the step that fixes
it, and `doctor` exits `4` when any check fails.

### Windows devices and labels

| Device | Advertised as | Labels |
|---|---|---|
| This machine | id `host`, named after the machine, with the Windows version | `windows` |

The machine is advertised only when the driver is ready (WinAppDriver 1.2.1
installed and Developer Mode on); otherwise the runner never claims Windows app
jobs and they stay queued for another runner. **One desktop app job at a time**
per runner, shared with Electron and Tauri: the app's windows, the mouse and
the keyboard belong to one desktop.

### Windows app builds

Upload builds on **QA → App builds** with the platform *Windows* (or with
[`builds upload --platform windows`](ci-integration.md#builds-upload)):

| File | Contains |
|---|---|
| **`.zip`** | The app folder: the executable and everything next to it |
| **`.exe`** | A portable executable that runs in place (not a setup program) |

Installers are refused, because they cannot run in place: upload a zip of the
app instead of an `.msi`. Downloading, checking, caching and unpacking work as
for [Electron builds](#electron-app-builds), including removing the
downloaded-from-the-internet mark (`Zone.Identifier`) from your own build, and
so does finding the executable (the first `.exe` at the top level, skipping
`Uninstall*.exe` and `*Update*.exe`). Set **Executable (optional)** on the
environment's app when the build holds several executables.

### Configure a Windows app on a test environment

Under **QA → Environments → your environment → Apps**, add a Windows app:

| Field | Meaning |
|---|---|
| App ID | The app's AppUserModelID (for packaged apps, e.g. `Microsoft.WindowsCalculator_8wekyb3d8bbwe!App`) or executable name (e.g. `notepad.exe`). Optional for builds and paths; needed for *Already installed*. Available to scripts as `{{app.id}}` |
| Executable (optional) | Path of the executable inside the build, relative to the unpacked build |
| App source | **Build**: an uploaded build. **Installed at path**: the absolute path of the executable or its folder on the runner (needs `builds.allow_local_paths`, as for [Electron](#configure-an-electron-app-on-a-test-environment)). **Already installed on the runner**: the app is started by its App ID — an AppUserModelID, or an executable on the runner's `PATH` |

To find a packaged app's AppUserModelID, run `Get-StartApps` in PowerShell.

### What a Windows app job does

1. Takes the runner's desktop slot (one desktop app job at a time).
2. Downloads, checks and unpacks the build and finds the executable, checks
   that the path on the runner exists (and is allowed), or uses the App ID.
3. Starts Appium with the Windows driver (the driver starts WinAppDriver on
   `127.0.0.1`) and opens a session that starts the app. A script's `launch
   {args}`, `terminate` and `focus_window {title}` work as described in
   [Windows and macOS actions](qa-automation-authoring.md#windows-and-macos-actions).
4. Runs the steps, then closes the app and ends the session.

The runner drives the real mouse and keyboard of that desktop. **Do not use
the machine while jobs run**: a click or key press of yours can land in the app
under test, and moving another window over it can make a step fail.

### Windows video and logs

- **Video** only when `ffmpeg` is on the runner's `PATH` (screen capture with
  `gdigrab`). Without ffmpeg, runs record no video whatever the run's video
  setting.
- **Screenshots** for steps are taken through the driver.
- **Failed steps** get the tail of the Appium log.

### Windows known limitations

- **An interactive, unlocked desktop session** is required; Session 0 (Windows
  Services), a locked screen and a minimised or disconnected Remote Desktop do
  not work.
- **WinAppDriver 1.2.1 only**, with Developer Mode on (it is the last
  WinAppDriver release). Controls that expose no UI Automation properties can
  only be reached with `control_type` and `nth` or with `xpath`; give them an
  AutomationId in the app.
- **Elevated apps** (apps that ask for administrator rights) cannot be driven
  from a runner that is not elevated itself, and the service runs without
  elevation.
- **No video without ffmpeg.**
- **Installers** (`.msi`) are not accepted as builds; install the app yourself
  and use *Already installed on the runner* or *Installed at path*.
- **Not in Docker**, and one desktop app job at a time per runner.

---

## macOS apps

Native macOS apps (AppKit, SwiftUI and Catalyst) are driven through the macOS
accessibility API: the runner starts Appium with its **Mac2** driver, which
runs XCTest's WebDriverAgentMac on the machine. macOS app jobs run on **Mac
runners** installed with the installer or npm, in a logged-in, unlocked user
session.

### macOS prerequisites

- **Full Xcode** (not only the Command Line Tools), opened once and selected:

  ```bash
  sudo xcode-select -s /Applications/Xcode.app
  ```

- **Accessibility permission** (*System Settings → Privacy & Security →
  Accessibility*) for the program that runs the runner, and for *Xcode Helper*
  (`/Applications/Xcode.app/Contents/Developer/Applications/Xcode Helper.app`)
  if it appears in that list after the first session. Which program runs the
  runner depends on how you start it:

  | Runner started | Grant Accessibility (and Automation) to |
  |---|---|
  | `leera-qa-runner start` in a terminal | The terminal app: **Terminal**, **iTerm** or the one you use |
  | As a service (`service install`, a LaunchAgent) | The runner's **`node` binary**: `/usr/local/lib/leera-qa-runner/<version>/node/bin/node` for the `.pkg` install, or the path `which node` prints for an npm install |

  Use the **+** button and pick the file (press *Cmd+Shift+G* to type a path).
  After updating the runner to a new version, the `.pkg` install's `node` path
  changes: grant the permission again and restart the service.
- **Automation permission.** The first time the runner controls an app, macOS
  asks whether the terminal or `node` may control it; allow it (*Privacy &
  Security → Automation* lists what was allowed).
- **Automation Mode.** The first session turns on macOS Automation Mode, and
  macOS asks for an administrator's name and password **on the Mac's own
  screen** (not in the terminal). If nobody enters it, the session fails and
  the job is blocked (see [macOS devices and labels](#macos-devices-and-labels)).
  Run `automationmodetool` (no arguments) to see whether that prompt is needed.
  On a dedicated test Mac an administrator can turn the prompt off by running
  this in Terminal themselves; the runner never runs it or changes the setting:

  ```bash
  sudo automationmodetool enable-automationmode-without-authentication
  ```
- **An unlocked, logged-in session.** Native UI tests cannot run behind a lock
  screen or screen saver, or while another user's session is in front (Fast
  User Switching). The service is a LaunchAgent in your GUI session, not a
  system daemon, for this reason. On a dedicated Mac turn on automatic login
  and turn off the screen lock and screen saver.
- **A build of the app for macOS**, the app at a path on the runner, or the app
  installed on the Mac (see [macOS app builds](#macos-app-builds)).

### Set up macOS apps

```bash
leera-qa-runner setup macos
```

`setup macos` checks Xcode, links the bundled Mac2 driver into the runner's
Appium home, checks that the driver's WebDriverAgentMac project is present
(Xcode builds it when the first session starts, which takes a minute or two),
clears a recorded permission refusal (below), and prints the Accessibility and
Automation steps above. It **never changes system settings or privacy
permissions** itself: macOS only lets you grant those in System Settings. Run
it again after granting them. It exits `0` when Xcode and the Mac2 driver are
ready and `4` otherwise; it cannot check the permissions themselves, so exit
`0` does not mean they are granted.

### Check macOS apps with doctor

```bash
leera-qa-runner doctor --platform macos
```

`doctor` checks full Xcode and the Mac2 driver, whether a job or session was
refused UI testing since the last `setup macos` (*macOS apps: Accessibility*),
whether Automation Mode will ask for a password (a warning), and `ffmpeg` for
video. A program cannot ask macOS in advance whether XCTest may drive the UI,
so *Accessibility* passes until a session is actually refused; a passing
`doctor` followed by blocked jobs still means a missing permission. `doctor`
exits `4` when any check fails.

### macOS devices and labels

| Device | Advertised as | Labels |
|---|---|---|
| This machine | id `host`, named after the machine, with the macOS version | `macos` |

The machine is advertised only when Xcode and the Mac2 driver are ready and no
permission refusal is recorded. **One desktop app job at a time** per runner,
shared with Electron and Tauri. iOS simulator jobs on the same Mac are not
affected.

When macOS refuses UI testing (Accessibility not granted, or the Automation
Mode password prompt was not answered), the job or session is **blocked** with:

> the runner needs Accessibility permission: System Settings → Privacy &
> Security → Accessibility → allow the app that starts the runner (…); the
> first session also enables Automation Mode, which asks for an administrator
> password on this Mac's screen; then run `leera-qa-runner setup macos`

The runner then records the refusal in the file `macos-accessibility-blocked`
in the runner home (`~/.leera-qa-runner/macos-accessibility-blocked`) and
**stops advertising the macOS device**, so further macOS app jobs stay queued
instead of being blocked one after another. `doctor` shows *macOS apps:
Accessibility* as failed and `service status` prints a line about it while the
file exists. To recover, grant the permission (or be at the Mac for the
Automation Mode prompt), then run:

```bash
leera-qa-runner setup macos
```

`setup macos` deletes the file; a running runner advertises the device again at
its next device refresh (restart it to pick it up at once).

### macOS app builds

Upload builds on **QA → App builds** with the platform *macOS* (or with
[`builds upload --platform macos`](ci-integration.md#builds-upload)):

| File | Contains |
|---|---|
| **`.zip`** | A zipped `.app` bundle (`ditto -c -k --keepParent MyApp.app MyApp.zip`) |
| **`.dmg`** | A disk image with the `.app` bundle |

Installer packages (`.pkg`) are refused: upload a zip of the app. Downloading,
checking, caching, unpacking, removing the quarantine mark from your own build,
and finding the executable (`<name>.app/Contents/MacOS/…`) work as for
[Electron builds](#electron-app-builds); **Executable (optional)** overrides
the detection.

The build must be allowed to run on the Mac: a Developer ID signed or ad-hoc
signed (`codesign -s -`) build of your own app works.

### Configure a macOS app on a test environment

| Field | Meaning |
|---|---|
| App ID | The bundle id, e.g. `com.example.MyApp`. Optional for builds and paths; required for *Already installed*. Available to scripts as `{{app.id}}` |
| Executable (optional) | Path of the executable inside the build, relative to the unpacked build |
| App source | **Build**: an uploaded build. **Installed at path**: the absolute path of the `.app` bundle on the runner (needs `builds.allow_local_paths`). **Already installed on the runner**: the app is started by its bundle id, e.g. an app in `/Applications` |

### What a macOS app job does

1. Takes the runner's desktop slot (one desktop app job at a time).
2. Downloads, checks and unpacks the build, checks that the path on the runner
   exists (and is allowed), or uses the bundle id.
3. Starts Appium with the Mac2 driver, which starts WebDriverAgentMac (built
   on first use) and then the app. A script's `launch {args}`, `terminate` and
   `focus_window {title}` work as described in
   [Windows and macOS actions](qa-automation-authoring.md#windows-and-macos-actions).
4. Runs the steps, then quits the app and ends the session.

As on Windows, the runner uses the real mouse and keyboard: **do not use the
Mac while jobs run**.

### macOS video and logs

- **Video** only when `ffmpeg` is on the runner's `PATH` (screen capture with
  `avfoundation`, which also needs *Screen Recording* permission for the same
  terminal or `node` binary). Without ffmpeg, runs record no video.
- **Screenshots** for steps are taken through the driver.
- **Failed steps** get the tail of the Appium log.

### macOS known limitations

- **An unlocked, logged-in GUI session** is required; the runner cannot run
  native UI tests behind the lock screen, as a system daemon, or over SSH
  without a logged-in desktop.
- **Privacy permissions are granted by hand** in System Settings (Accessibility,
  Automation, and Screen Recording for video), per program, and again when the
  `node` path changes after an update.
- **Hosted CI Macs** may not grant Accessibility to the runner; see
  [CI integration](ci-integration.md#native-windows-and-macos-apps-in-ci).
- **Controls without accessibility information** can only be reached by `role`
  with `nth`, `predicate` or `class_chain`; give them an identifier in the app.
- **No video without ffmpeg.**
- **Not in Docker**, and one desktop app job at a time per runner.

---

## Device sessions

A device session lets an AI agent explore an app on a real device before it
writes a script. The agent asks the instance for a session over MCP; a runner
with an idle device of that platform claims it, installs and launches the app,
and then executes the agent's commands one at a time: take a snapshot (a
screenshot plus the screen's element tree), tap, type, swipe, go back, and any
script action. Every result comes back with a fresh screenshot and the target
the agent should save in its script. How agents use it is described in
[qa-automation-authoring.md](qa-automation-authoring.md#device-sessions). Sessions
work on Android and iOS devices and on Electron, Tauri, Windows and macOS apps
(iOS has no back key: `back` is refused there; desktop apps have neither `back`
nor `home`).

- **Runners handle sessions automatically**; nothing needs to be switched on.
  A runner that supports sessions long-polls for commands while it holds one.
- **The device is busy** for the session's lifetime: jobs wait for another
  device.
- **Limits.** A session ends when the agent ends it, after 10 minutes without a
  command, after 60 minutes in total, when the runner stops, or when the device
  is lost. A session no runner picks up within 2 minutes expires. Each command
  times out after 30 s by default (`wait_for` up to 60 s).
- **What a session cannot do.** Commands are UI actions only: no shell, no
  script execution, no file access on the device or the runner.
- **CI tokens never serve sessions**; a session needs a runner connected with an
  ordinary token.
- **Who can see them.** Live sessions appear on the Test runners page under
  **Live device sessions**, and next to the device on the runner's row. Only the
  person who started a session, or a workspace administrator, can drive or end
  it.

---

## CI runners

A pipeline can run a test run on the CI machine itself with
`leera-qa-runner ci`, using a **CI token** (a token of kind *CI*, bound to one
project) instead of a long-lived runner. The command registers an *ephemeral*
runner bound to the run it creates, runs the jobs, and exits with the verdict.
Ephemeral runners are listed under **CI runners** on the Test runners page and
are deleted an hour after they go offline. They never claim device sessions.

CI tokens, the command's flags, app builds from the pipeline, JUnit and job
summary reports, exit codes and ready-made GitHub Actions and GitLab CI
templates are described in [Running automated tests from CI](ci-integration.md).

---

## Updating

Runner and server share one version number. The Test runners page marks runners
that are behind ("Update available", with the command in its tooltip) or below
the instance's minimum ("Too old").

```bash
leera-qa-runner update --check     # exit 0: up to date, 10: an update is available
leera-qa-runner update             # asks before installing
leera-qa-runner update --yes       # no prompt (scripts, remote shells)
leera-qa-runner update --version 0.4.7
```

`--check` compares this runner with the latest version the instance reported
when the runner last registered, or, before that, with the latest release.
`update` then updates the way the runner was installed (recorded in
`~/.leera-qa-runner/install.json`):

| Installed with | What `update` does |
|---|---|
| `.pkg`, `.exe`, install script, `.tar.gz` | Downloads the update archive for this OS and architecture, verifies it, unpacks it into `~/.leera-qa-runner/versions/<version>`, switches `versions/current` to it and restarts the background service if one is installed. No administrator rights needed; the two newest versions are kept |
| npm | Prints `npm install -g @leera/qa-runner@<version>` (`@latest` without `--version`); runs it with `--yes` |
| Homebrew | Prints `brew upgrade --cask leera-qa-runner`; runs it with `--yes`. Homebrew always installs the cask's current version, so `--version` is ignored |
| winget | Prints `winget upgrade --id Leera.QARunner --exact` (with `--version` when you pass one); runs it with `--yes` |
| Docker | Prints the `docker pull` to run; recreate the container with the new tag |

The launcher installed by the `.pkg`, `.exe` or tarball keeps working after an
update: it starts `versions/current` whenever that version is newer than its own.

**Verification.** Each release carries `releases.json`, a manifest listing every
update archive with its size and SHA-256, and `releases.json.sig`, an Ed25519
signature of that manifest. Runners from the `.pkg`, `.exe` and tarball of a
signed release carry the release public key and refuse to install from a manifest whose signature is
missing or invalid (exit `1`). A runner without the key (npm installs and
development builds) checks the archive's SHA-256 against the manifest fetched
over HTTPS and prints a warning that the manifest is not signature-checked.

**Rolling back.** Install the previous version the same way:
`leera-qa-runner update --version <old version> --yes`. A version still in
`versions/` is switched to without downloading its archive again.

After updating, check the runner with `leera-qa-runner version` and, for app
platforms, `leera-qa-runner doctor`. On macOS, an update moves the runner's
`node` to a new path, so grant Accessibility or Automation again where
[macOS apps](#macos-apps) need it.

## Revoking a runner

- **Token compromised or machine retired:** revoke the token on the Test
  runners page. Every runner using it stops at its next request (exit code 3).
- **Remove the program:** `leera-qa-runner service uninstall`, then remove the
  install (`/usr/local/lib/leera-qa-runner` and the `/usr/local/bin` link on
  macOS; *Apps & features* on Windows; the unpacked directory on Linux;
  `npm uninstall -g @leera/qa-runner`; `brew uninstall --cask leera-qa-runner`;
  `winget uninstall Leera.QARunner`), and delete `~/.leera-qa-runner`, which
  also holds the versions `update` installed.

## Security

- **What a runner can do.** Claim jobs from its own pool, and record their
  results, evidence and logs. It cannot read other projects, tickets or users.
- **What it receives.** The test script, the environment's base URL, for
  app platforms the app's id and a short-lived download link for the app build
  (or, for desktop apps, the path of the app on the runner), and, when a run
  is queued with a QA credential, that account's **username and password**.
  Treat a runner machine like any place those accounts could be used from, and
  revoke the token if the machine is compromised.
- **Secrets in results.** Credential values are redacted from step notes and
  debug logs; network logs keep method, URL, status and timing only (no headers
  or bodies), and secret-looking query values are masked.
- **Token storage.** The token is stored in a `0600` file (never in
  `config.json`), and `connect` reads it from a hidden prompt or stdin rather
  than a command-line argument.
- **Network.** Outbound HTTPS to your instance and its file storage (app build
  downloads) only, plus the sites under test, the browser download from `setup
  browsers`, the SDK packages `setup android --install-sdk` fetches and the
  WinAppDriver installer `setup windows` downloads from Microsoft's GitHub
  releases (checked against a pinned SHA-256). WebDriverAgent and
  WebDriverAgentMac are built locally from the bundled drivers' sources.
- **iOS signing.** Real-device jobs sign WebDriverAgent with the identity in the
  runner user's keychain for `ios.team_id`. The runner never exports or uploads
  certificates.
- **CI tokens** are bound to one project: they can start runs, upload builds and
  run jobs there, and nothing else. Their runs act as the person who created the
  token.
- **Device sessions.** An agent driving a device through a session can only
  send UI commands (snapshots, taps, typing, swipes, the script actions). There
  is no shell, script execution or file access on the device or the runner.
- **Integrity.** Installer downloads are verified against the release's
  `SHA256SUMS`. macOS packages are signed and notarized; the Windows installer
  is not signed yet.

---

## Troubleshooting

**The runner does not appear on the Test runners page.** Run
`leera-qa-runner doctor`. Check the URL is the address users open in the
browser (with `https://`), and that the machine can reach it
(`curl -I https://leera.example.com` from that machine).

**"token rejected" / exit code 3.** The token was revoked, belongs to a
different instance, or was pasted incompletely. Create a new one and run
`leera-qa-runner config set-token`.

**Exit code 5: the server needs a newer runner.** The instance sets a minimum
runner version. [Update](#updating) the runner.

**Jobs stay queued.** Check that a runner in the *same pool* is online and
idle, and that its labels include what the job needs (`web-chromium` for web
jobs, `android` for Android jobs, `ios` for iOS jobs, `electron` for Electron
jobs, `tauri` for Tauri jobs, `windows` and `macos` for native app jobs), and
— for every platform but web — that one of its devices is free
(a device in a live session is busy).
`leera-qa-runner doctor --platform <platform>` explains a missing label.

**Every step is blocked with "the environment could not be reached".** The
base URL is not reachable *from the runner machine*. For a site on the same
machine as a Docker runner, use `host.docker.internal`.

**Chromium fails to start on Linux.** Run `leera-qa-runner setup browsers` and
the `install-deps` command it prints. In Docker, keep `--shm-size=1g`.

**The service works in the terminal but not in the background.** The service
has a different environment. Re-run `leera-qa-runner service install` from a
shell where `leera-qa-runner doctor` passes, then check
`leera-qa-runner service logs`.

**Android jobs are blocked with "the Android device is not ready".** Run
`leera-qa-runner doctor --platform android`. For an emulator, check
`~/.leera-qa-runner/logs/emulator-<id>.log`; on Linux the usual cause is
`/dev/kvm` (see [prerequisites](#prerequisites)). For a phone, unlock it and
accept the USB debugging prompt.

**"the app build is not available" / "is not installed".** The environment
installs a build, but none is ready for the project, or the environment says
*Already installed on the runner* and the package is not on that device. Upload
an `.apk`, or install the app on every device first.

**Android works in the terminal but not as a service.** The service did not
inherit `ANDROID_HOME`/`JAVA_HOME`. Re-run `leera-qa-runner service install`
from a shell where `doctor --platform android` passes, or set
`android.sdk_path` in `config.json`.

**`doctor --platform ios` or `setup ios` says full Xcode is needed.**
Xcode is not installed, or `xcode-select -p` points at the Command Line Tools.
Run `sudo xcode-select -s /Applications/Xcode.app`, open Xcode once, and run
`leera-qa-runner setup ios` again.

**The first iOS job on a simulator is very slow or blocked with "Appium could
not start a session".** WebDriverAgent was not prebuilt for this driver and
Xcode version (for example after an Xcode update). Run `leera-qa-runner setup
ios`; if the build fails, read `~/.leera-qa-runner/wda/<dir>.build.log`.

**"this build is an .ipa; simulators need a zipped .app …" / "this build is a
simulator .app; real devices need an .ipa …".** The run's build does not fit
the device kind. Upload a simulator build for simulators, an `.ipa` for devices,
or require `ios-simulator` / `ios-real` when queueing.

**Real device jobs are blocked with "real iOS devices need your Apple Developer
Team ID".** Set `ios.team_id` ([Real devices](#real-ios-devices)). If the session
still does not start, check that the device is unlocked, paired, has Developer
Mode on, and trusts your developer certificate, and that the signing identity is
in the keychain of the user running the runner.

**Electron jobs are blocked because no executable was found.** The build holds
no executable where the runner looks for one ([Electron app
builds](#electron-app-builds)), or several. Set **Executable (optional)** on the
environment's app to the path inside the build.

**Electron jobs on a path are blocked.** The runner does not allow local paths:
`leera-qa-runner config set builds.allow_local_paths true`, then restart it.
Check that the path exists on that runner.

**Electron apps do not start on Linux.** Run `leera-qa-runner doctor --platform
electron`. Without a display, install Xvfb (`sudo apt-get install -y xvfb`);
check that the app starts by hand, which shows missing system libraries.

**A Tauri runner shows no `tauri` label.** Run `leera-qa-runner doctor
--platform tauri`. On Linux, install `webkit2gtk-driver` and `tauri-driver`
2.0.6; on Windows, set `tauri.native_driver_path` to an `msedgedriver` that
matches WebView2; as a service, set `tauri.driver_path`. On a Mac, the label
appears only with `tauri.macos_plugin` on ([Tauri on macOS](#tauri-on-macos)).

**Tauri jobs on Windows stop working after an update.** WebView2 updated and
`msedgedriver` no longer matches it. Download the matching driver.

**"Tauri on macOS needs a build with the embedded WebDriver plugin".** The
Mac runner has `tauri.macos_plugin` on, but the build does not answer on
`TAURI_WEBDRIVER_PORT`: it was built without the plugin (a release build, or
without the feature that registers it). Upload a test build with the plugin.

**CI: `leera-qa-runner ci` exits with a code other than 0 or 10.** See
[CI exit codes](ci-integration.md#exit-codes) and
[known limitations](ci-integration.md#known-limitations).

**Windows app jobs fail at once or time out on every action.** The runner is
not in an interactive desktop: it runs as a Windows Service, the screen is
locked, or the Remote Desktop window is minimised or disconnected. Run
`leera-qa-runner doctor --platform windows`, use `service install` (a
scheduled task at logon) and keep the session unlocked. Check that Developer
Mode is still on.

**A Windows runner shows no `windows` label.** WinAppDriver 1.2.1 is missing
or Developer Mode is off. Run `leera-qa-runner setup windows` and follow what
it prints.

**macOS app jobs fail at the first action, or the session never starts.** The
program running the runner lacks Accessibility (or Automation) permission, or
the screen is locked. Grant the permission to the terminal (interactive) or to
the runner's `node` binary (service) as described in
[macOS prerequisites](#macos-prerequisites), then restart the runner. After an
update of a `.pkg` install, grant it again for the new `node` path.

**macOS app jobs are blocked with "the runner needs Accessibility permission",
and the Mac no longer takes macOS app jobs.** macOS refused UI testing: the
permission is missing, or Automation Mode asked for an administrator password
on the Mac's screen and nobody entered it. Grant the permission (or be at the
Mac for the prompt; on a dedicated test Mac an administrator can run
`sudo automationmodetool enable-automationmode-without-authentication` in
Terminal once to turn the prompt off), then run `leera-qa-runner setup macos`,
which clears the recorded refusal
(`~/.leera-qa-runner/macos-accessibility-blocked`) so the Mac advertises its
macOS device again. See [macOS devices and labels](#macos-devices-and-labels).

**Windows: "Windows protected your PC".** The installer is not signed yet; see
[Windows](#windows).

