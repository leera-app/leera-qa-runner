# Running automated tests from CI

CI mode lets a pipeline start a test run for the commit it builds, execute the
run's automated cases on the CI machine itself, and pass or fail the pipeline
with the result — without a long-lived runner. One command does all of it:

```bash
leera-qa-runner ci --platform web --environment staging --junit qa-results/junit.xml
```

Everything the command needs besides its flags comes from two CI secrets:
`RUNNER_URL` (the instance URL users open in the browser) and `RUNNER_TOKEN` (a
**CI token**, below). How runners, pools and tokens work in general is described
in [Test runners](test-runners.md); how the scripts are written is in
[Authoring automated test cases](qa-automation-authoring.md).

- [CI tokens](#ci-tokens)
- [The `ci` command](#the-ci-command)
- [App builds](#app-builds)
- [Reports](#reports)
- [Exit codes](#exit-codes)
- [Templates](#templates)
- [Known limitations](#known-limitations)

---

## CI tokens

A CI token is a pool token of kind **CI**, bound to one project.

**Create one.** Open **QA → Test runners** (or **Workspace settings → Test
runners**), choose the pool the CI runs should use, click **New token**, pick
**Kind: CI**, choose the **Project**, and name it after the pipeline (for
example *GitHub Actions*). The token (`pm_run_…`) is shown once; store it as the
CI secret `RUNNER_TOKEN`, next to `RUNNER_URL`. The dialog then shows
ready-made pipeline steps with your instance's URL and the project filled in.

What a CI token can do:

- **Start test runs in its project**, read their status and cancel them.
  Naming any other project is refused (HTTP 403, exit code `3`).
- **Upload app builds to its project** (`leera-qa-runner builds upload`, or
  `ci --upload-build`).
- **Register runners and run jobs** from its pool, for its project only. Every
  runner a CI token registers is **ephemeral**: it is bound to the run the
  command created, is listed under **CI runners** on the Test runners page, and
  is **deleted an hour after it goes offline**.

What it cannot do:

- **Claim device sessions.** Agents exploring an app over MCP need a runner with
  an ordinary (kind *Runner*) token.
- Read or change anything outside its project.

**Who a run belongs to.** Runs a CI token starts are created as the person who
created the token, so that person needs permission to execute test runs in the
project. The run records the commit, the branch, the CI provider and the
pipeline URL, and the run list marks it with a **CI** chip. If the token
creator's account is removed, the token stops working; create a new one.

**Revoking.** Revoke the token on the Test runners page like any other token;
pipelines using it then exit with code `3`.

---

## The `ci` command

```text
leera-qa-runner ci --environment ENV --platform PLATFORM [options]
```

| Flag | Default | Meaning |
|---|---|---|
| `--environment SLUG\|ID` | `RUNNER_ENVIRONMENT` | **Required.** The test environment, by slug (case-insensitive) or numeric id |
| `--platform NAME` | `RUNNER_PLATFORM` | **Required.** `web`, `android`, `ios`, `electron`, `tauri`, `windows` or `macos` |
| `--project KEY\|ID` | `RUNNER_PROJECT`, else the CI token's project | The project, by key or numeric id. It must be the token's project |
| `--plan NAME\|ID` | none | A test plan, by name (case-insensitive) or id. Without a plan the run holds **every active test case of the project that has a script for the platform** |
| `--build PATH` | none | An app build file on the CI machine (`.apk`; `.ipa` or a zipped `.app` for iOS; `.zip`, `.AppImage`, `.exe` or `.dmg` for Electron and Tauri; `.zip` or `.exe` for Windows apps; `.zip` or `.dmg` for macOS apps). Kept on this machine unless `--upload-build` |
| `--upload-build` | off | Upload `--build` to the project first, so the build is kept and other runners can use it |
| `--build-id N` | none | Test a build that was already uploaded |
| `--version-name TEXT` | none | With `--upload-build`: the version name to store. Without any build flag: test the newest ready build of the platform with this version name |
| `--build-number TEXT` | none | Likewise, for the build number |
| `--name TEXT` | `CI <platform> <branch>@<short sha>` | The test run's name |
| `--video MODE` | `on_failure` | `off`, `on_failure` or `always` |
| `--timeout MINUTES` | `60` | Cancel the run and exit `12` after this long, counted from the command's start |
| `--junit PATH` | none | Write a JUnit XML report (missing directories are created) |
| `--labels a,b` | detected | Use exactly these runner labels |
| `--concurrency N` | `1` | Browser jobs at once |
| `--skip-doctor` | off | Do not check the machine first |

`--build` together with `--build-id`, `--upload-build` without `--build`, and a
build for a web run all exit `2`.

### What it does

1. **Checks the machine** with `doctor` for the platform (unless
   `--skip-doctor`). Like `doctor --fix`, it creates the runner home and, for
   web, downloads Chromium when it is missing. When a check still fails it
   prints the report and exits `4`. It does not build WebDriverAgent: run
   `leera-qa-runner setup ios` before `ci` for iOS (the template does).
2. **Reads the pipeline's facts**: provider, commit, branch, pipeline URL,
   repository, run number and attempt. GitHub Actions, GitLab CI, Buildkite and
   CircleCI are recognised; any other CI that sets `CI=true` is reported as `ci`.
   A commit, branch or repository the provider does not expose is read from
   `git` in the working directory.
3. **Prepares the build**: hashes `--build` (SHA-256), and uploads it first with
   `--upload-build`.
4. **Registers an ephemeral runner** named `ci-<repo>-<run>-<attempt>`, so a
   re-run of the same pipeline job registers a new one.
5. **Creates the test run** for the project, plan, environment and platform,
   with the commit, branch, provider and pipeline URL, and queues its automated
   cases in the token's pool. Cases that cannot be queued (for example a
   sign-in role without a usable credential) are reported as *not queued*.
6. **Binds the runner to the run** (it registers again with the run's id) and
   runs the run's jobs on this machine, polling the run's status every 10
   seconds.
7. **Finishes** when no job is queued or running any more: prints a summary,
   appends it to the GitHub Actions job summary, writes `--junit`, and exits with
   the verdict.

On `--timeout`, `SIGINT` or `SIGTERM` the command cancels the run's remaining
jobs before exiting; a second signal exits at once.

**Electron** jobs run one at a time on the CI machine. On Linux without a
display the runner starts Xvfb itself, so install the `xvfb` package on the
machine first; nothing else is set up for Electron (`setup electron` installs
nothing; it only reminds a Linux machine without a display to install Xvfb).

**Tauri** jobs run one at a time on a **Linux or Windows** CI machine, which
needs `tauri-driver` 2.0.6 and the native WebDriver server installed first (see
[Tauri in CI](#tauri-in-ci)); the `doctor` check at the start exits `4` when
either is missing. macOS CI machines cannot run Tauri jobs for ordinary builds.

**Devices it booted.** When the command exits, for any reason, it shuts down
the Android emulators and iOS simulators its runner booted for the jobs.
Emulators and simulators that were already running when it started are left
running.

**Which runners take the jobs.** Jobs of a local build (`--build` without
`--upload-build`) are pinned to the `ci` command's runner and never run anywhere
else. Web jobs and jobs of uploaded builds can also be claimed by other online
runners in the same pool; give CI tokens a pool of their own when every job
should run on the CI machine.

---

## App builds

Android, iOS, Electron, Tauri, Windows and macOS runs install the app under
test from a build (a desktop app environment can instead name a path on the
runner, and a Windows or macOS one an app already installed there). The `ci` command
takes one of these:

| You pass | The build | Use when |
|---|---|---|
| `--build PATH` | Stays on the CI machine. Only this command's runner can run the jobs; nothing is uploaded or kept | The pipeline builds the app and tests it in the same job (the templates do this) |
| `--build PATH --upload-build` | Uploaded to the project first (listed on **QA → App builds** with the commit and branch), then tested | The build should be kept for later runs, device sessions or other runners |
| `--build-id N` | An uploaded build | An earlier job uploaded it (`builds upload` prints the id) |
| none of these | `--version-name` / `--build-number`: the newest ready build with that version; otherwise the environment's default build, else the newest ready build | The app is built and uploaded elsewhere |

Build files: Android **`.apk`** (app bundles are refused). iOS: an **`.ipa`** for
real devices, or a **zipped `.app` built for the simulator**
(`xcodebuild -sdk iphonesimulator`) for simulators — see
[iOS app builds](test-runners.md#ios-app-builds). Electron: a **`.zip`** of the
packaged app directory or `.app` bundle, an **`.AppImage`**, a portable
**`.exe`** or a **`.dmg`**, built for the CI machine's operating system — see
[Electron app builds](test-runners.md#electron-app-builds). Tauri: a **`.zip`**
of the app folder, an **`.AppImage`** or the portable **`.exe`** (installers
such as `.msi` and `.deb` are refused) — see
[Tauri app builds](test-runners.md#tauri-app-builds). Windows apps: a **`.zip`**
of the app folder or a portable **`.exe`**; macOS apps: a zipped **`.app`** or
a **`.dmg`** (`.msi` and `.pkg` installers are refused) — see
[Windows app builds](test-runners.md#windows-app-builds) and
[macOS app builds](test-runners.md#macos-app-builds). The upload size limit is 500 MB
by default (`QA_BUILD_MAX_MB` on self-hosted instances).

### `builds upload`

Uploads a build with a CI token and prints its id:

```bash
BUILD_ID=$(leera-qa-runner builds upload app-release.apk --platform android --version-name 1.4.0)
leera-qa-runner ci --platform android --environment staging --build-id "$BUILD_ID"
```

| Flag | Meaning |
|---|---|
| `PATH` | The build file (exactly one) |
| `--platform NAME` | **Required.** `android`, `ios`, `electron`, `tauri`, `windows` or `macos` (web takes no builds) |
| `--project KEY\|ID` | The project; default `RUNNER_PROJECT`, else the CI token's project |
| `--version-name TEXT` | Version name shown in the workspace |
| `--build-number TEXT` | Build number |
| `--app-id ID` | Package name, bundle id, Electron or Tauri app id, or Windows AppUserModelID or executable name |
| `--notes TEXT` | Notes |
| `--git-sha SHA` | Commit the build came from; default detected from the CI environment or `git` |
| `--git-branch NAME` | Branch; likewise |
| `--relay` | Send the file through the API instead of straight to storage |
| `--json` | Print the whole build as JSON instead of its id |

The file goes straight to object storage with a presigned URL; when that fails
(CORS, a proxy refusing the body) the command falls back to sending it through
the API, which has its own, lower limit (`QA_BUILD_RELAY_MAX_MB`, 100 MB by
default). Exit codes: `0` uploaded, `2` usage error or an upload the server
refused (wrong file type, too large), `3` token refused, including a project
other than the token's own or one that does not exist (HTTP 403), `1` anything
else.

---

## Reports

**Console.** A summary with the verdict, the counts (passed, failed, blocked,
skipped, pending), the cases this runner executed with their failures, the cases
that were not queued, and the link to the run's report.

**GitHub Actions job summary.** When `$GITHUB_STEP_SUMMARY` is set, the same
summary is appended to it as Markdown: a heading linking to the run with the
verdict, the counts, a table of the executed cases, and a collapsed list of the
cases that were not queued.

**JUnit** (`--junit PATH`). One `<testsuite>` named after the run, with one
`<testcase>` per case this runner executed: failed cases carry `<failure>`, job
errors `<error>`, blocked and skipped cases `<skipped>`. Cases that were not
queued are added as `<skipped>` with the reason. The suite's properties hold the
run id, platform, report URL, run status and item counts; cases executed by
other runners in the pool only appear in those counts. GitLab reads the file
through `artifacts:reports:junit`; on GitHub, upload it as an artifact or pass it
to a test-report action.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Every case passed |
| 1 | Error: nothing was queued (no case of the run could be automated on this platform), the runner stopped on an error, or the run's final status could not be read |
| 2 | Usage or configuration error: a missing or conflicting flag, `RUNNER_URL`/`RUNNER_TOKEN` not set, or a request the server refused as invalid (unknown environment, plan or build; no active case with a script for the platform when no plan is given) |
| 3 | The server refused the token (revoked, not a CI token, another project) |
| 4 | The machine is not ready (`doctor` failed) |
| 5 | The instance refuses this runner version; install the instance's version |
| 10 | At least one case failed |
| 11 | No failures, but cases were blocked, or are still pending (not executed) |
| 12 | `--timeout` passed; the run was cancelled |
| 13 | The run was cancelled (for example from the app) |
| 130 | Interrupted (`SIGINT`/`SIGTERM`); the run was cancelled |

To keep a pipeline green when cases are only blocked, accept `11` in the step:
`leera-qa-runner ci … || [ $? -eq 11 ]`.

---

## Templates

Complete pipelines for GitHub Actions (web, Android, iOS) and GitLab CI (web).
There are no desktop app templates yet; see [Electron in CI](#electron-in-ci),
[Tauri in CI](#tauri-in-ci) and
[Native Windows and macOS apps in CI](#native-windows-and-macos-apps-in-ci).
The same files are in the runner's source under
[`qa-runner/ci-templates/`](../qa-runner/ci-templates). Each installs the runner
with npm at a pinned version: **keep `LEERA_QA_RUNNER_VERSION` at your
instance's version**. Replace the environment slug (`staging`) and the app build
steps with your own. Every template reads the secrets `RUNNER_URL` and
`RUNNER_TOKEN`.

### GitHub Actions: web

Installs Chromium (cached) and its system libraries, then runs the project's web
cases against a deployed environment.

```yaml
name: QA (web)

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: qa-web-${{ github.ref }}
  cancel-in-progress: true

jobs:
  qa-web:
    runs-on: ubuntu-24.04
    timeout-minutes: 70
    env:
      RUNNER_URL: ${{ secrets.RUNNER_URL }}
      RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
      # The runner version this workflow installs; keep it at your server's version.
      LEERA_QA_RUNNER_VERSION: "0.4.6"
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install the QA runner
        run: npm install -g "@leera/qa-runner@${LEERA_QA_RUNNER_VERSION}"

      - name: Cache Chromium
        uses: actions/cache@v4
        with:
          path: ~/.leera-qa-runner/browsers
          key: leera-qa-browsers-${{ runner.os }}-${{ env.LEERA_QA_RUNNER_VERSION }}

      - name: Install Chromium and its system libraries
        run: |
          leera-qa-runner setup browsers
          sudo "$(command -v node)" "$(npm root -g)/@leera/qa-runner/node_modules/playwright-core/cli.js" install-deps chromium

      - name: Run the web tests
        run: |
          leera-qa-runner ci \
            --platform web \
            --environment staging \
            --timeout 60 \
            --junit qa-results/junit.xml

      - name: Keep the JUnit report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qa-web-junit
          path: qa-results/junit.xml
          if-no-files-found: ignore
```

### GitHub Actions: Android

Builds the APK, enables KVM (Android emulators are unusably slow without it),
caches an API 35 emulator snapshot, and runs the cases on that emulator with the
local build.

```yaml
name: QA (Android)

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: qa-android-${{ github.ref }}
  cancel-in-progress: true

env:
  API_LEVEL: 35
  EMULATOR_TARGET: google_apis
  EMULATOR_ARCH: x86_64

jobs:
  qa-android:
    runs-on: ubuntu-24.04
    timeout-minutes: 90
    env:
      RUNNER_URL: ${{ secrets.RUNNER_URL }}
      RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
      # The runner version this workflow installs; keep it at your server's version.
      LEERA_QA_RUNNER_VERSION: "0.4.6"
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Build the app
        run: ./gradlew assembleDebug

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Install the QA runner
        run: |
          npm install -g "@leera/qa-runner@${LEERA_QA_RUNNER_VERSION}"
          leera-qa-runner setup android

      - name: Cache the emulator
        uses: actions/cache@v4
        id: avd-cache
        with:
          path: |
            ~/.android/avd/*
            ~/.android/adb*
          key: avd-${{ env.API_LEVEL }}-${{ env.EMULATOR_TARGET }}-${{ env.EMULATOR_ARCH }}

      - name: Create the emulator snapshot
        if: steps.avd-cache.outputs.cache-hit != 'true'
        uses: reactivecircus/android-emulator-runner@v2.38.0
        with:
          api-level: ${{ env.API_LEVEL }}
          target: ${{ env.EMULATOR_TARGET }}
          arch: ${{ env.EMULATOR_ARCH }}
          force-avd-creation: false
          emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
          disable-animations: false
          script: echo "Emulator snapshot created for the cache."

      - name: Run the Android tests
        uses: reactivecircus/android-emulator-runner@v2.38.0
        with:
          api-level: ${{ env.API_LEVEL }}
          target: ${{ env.EMULATOR_TARGET }}
          arch: ${{ env.EMULATOR_ARCH }}
          force-avd-creation: false
          emulator-options: -no-snapshot-save -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
          disable-animations: true
          # Each line runs on its own; keep the command on one line.
          script: leera-qa-runner ci --platform android --environment staging --build app/build/outputs/apk/debug/app-debug.apk --timeout 60 --junit qa-results/junit.xml

      - name: Keep the JUnit report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qa-android-junit
          path: qa-results/junit.xml
          if-no-files-found: ignore
```

### GitHub Actions: iOS

Runs on `macos-15`. Caches WebDriverAgent by XCUITest driver version and Xcode
version (building it takes several minutes), builds the app for the simulator,
zips the `.app`, and runs the cases on a simulator with that local build.

```yaml
name: QA (iOS)

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: qa-ios-${{ github.ref }}
  cancel-in-progress: true

jobs:
  qa-ios:
    runs-on: macos-15
    timeout-minutes: 90
    env:
      RUNNER_URL: ${{ secrets.RUNNER_URL }}
      RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
      # The runner version this workflow installs; keep it at your server's version.
      LEERA_QA_RUNNER_VERSION: "0.4.6"
      SCHEME: MyApp
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install the QA runner
        run: npm install -g "@leera/qa-runner@${LEERA_QA_RUNNER_VERSION}"

      - name: Read the Xcode and XCUITest driver versions
        id: versions
        run: |
          echo "xcode=$(xcodebuild -version | awk 'NR==1 {print $2}')" >> "$GITHUB_OUTPUT"
          echo "driver=$(node -p "require('$(npm root -g)/@leera/qa-runner/node_modules/appium-xcuitest-driver/package.json').version")" >> "$GITHUB_OUTPUT"

      # Building WebDriverAgent takes minutes; reuse it while Xcode and the driver stay the same.
      - name: Cache WebDriverAgent
        uses: actions/cache@v4
        with:
          path: ~/.leera-qa-runner/wda
          key: wda-${{ steps.versions.outputs.driver }}-xcode-${{ steps.versions.outputs.xcode }}

      - name: Prepare iOS automation
        run: leera-qa-runner setup ios

      - name: Build the app for the simulator
        run: |
          xcodebuild build \
            -scheme "$SCHEME" \
            -sdk iphonesimulator \
            -configuration Debug \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO
          cd build/Build/Products/Debug-iphonesimulator
          zip -qry "$GITHUB_WORKSPACE/$SCHEME.zip" "$SCHEME.app"

      - name: Run the iOS tests
        run: |
          leera-qa-runner ci \
            --platform ios \
            --environment staging \
            --build "$SCHEME.zip" \
            --timeout 60 \
            --junit qa-results/junit.xml

      - name: Keep the JUnit report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qa-ios-junit
          path: qa-results/junit.xml
          if-no-files-found: ignore
```

### GitLab CI: web

Set `RUNNER_URL` and `RUNNER_TOKEN` as masked CI/CD variables. The runner home
is moved into the project directory so GitLab can cache Chromium.

```yaml
qa-web:
  stage: test
  image: node:22-bookworm
  timeout: 70 minutes
  variables:
    # The runner version this job installs; keep it at your server's version.
    LEERA_QA_RUNNER_VERSION: "0.4.6"
    # Inside the project directory so GitLab can cache the browser.
    LEERA_RUNNER_HOME: "$CI_PROJECT_DIR/.leera-qa-runner"
  cache:
    key: "leera-qa-browsers-$LEERA_QA_RUNNER_VERSION"
    paths:
      - .leera-qa-runner/browsers
  script:
    - npm install -g "@leera/qa-runner@${LEERA_QA_RUNNER_VERSION}"
    - leera-qa-runner setup browsers
    - node "$(npm root -g)/@leera/qa-runner/node_modules/playwright-core/cli.js" install-deps chromium
    - leera-qa-runner ci --platform web --environment staging --timeout 60 --junit qa-results/junit.xml
  artifacts:
    when: always
    paths:
      - qa-results/junit.xml
    reports:
      junit: qa-results/junit.xml
```

### Electron in CI

Build the app in the job, then run `ci` with the build. On a Linux machine,
install Xvfb first:

```yaml
      - run: sudo apt-get update && sudo apt-get install -y xvfb
      - run: npm install -g @leera/qa-runner@${{ env.LEERA_QA_RUNNER_VERSION }}
      - run: npm ci && npm run make           # your own Electron build
      - run: >-
          leera-qa-runner ci --platform electron --environment staging
          --build dist/MyApp-linux-x64.zip
          --junit qa-results/junit.xml
        env:
          RUNNER_URL: ${{ secrets.RUNNER_URL }}
          RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
```

On macOS and Windows machines skip the Xvfb step and pass that operating
system's build (a zipped `.app` or a `.dmg`; a zipped app directory or a
portable `.exe`). When the build holds more than one executable, set
**Executable (optional)** on the environment's Electron app.

### Tauri in CI

Tauri jobs need a **Linux or Windows** CI machine. Build the app in the job,
install the WebDriver pieces, then run `ci` with the build.

On **Linux** (GitHub's `ubuntu-latest` shown), with Xvfb for the missing
display:

```yaml
      - run: |
          sudo apt-get update
          # WebKitWebDriver and Xvfb for the runner; the rest to build a Tauri 2 app
          sudo apt-get install -y webkit2gtk-driver xvfb \
            libwebkit2gtk-4.1-dev build-essential libssl-dev \
            libayatana-appindicator3-dev librsvg2-dev
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo install tauri-driver --version 2.0.6 --locked
      - run: npm install -g @leera/qa-runner@${{ env.LEERA_QA_RUNNER_VERSION }}
      - run: npm ci && npm run tauri build -- --bundles appimage    # your own Tauri build
      - run: >-
          leera-qa-runner ci --platform tauri --environment staging
          --build src-tauri/target/release/bundle/appimage/MyApp_1.0.0_amd64.AppImage
          --junit qa-results/junit.xml
        env:
          RUNNER_URL: ${{ secrets.RUNNER_URL }}
          RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
```

On **Windows**, install `tauri-driver` the same way and an `msedgedriver` that
matches the machine's WebView2 version (hosted Windows images update WebView2,
so fetch the driver in the job rather than caching it). Tell the runner where
the driver is, and pass the portable executable Cargo builds:

```yaml
      - run: cargo install tauri-driver --version 2.0.6 --locked
      - run: npm install -g @leera/qa-runner@${{ env.LEERA_QA_RUNNER_VERSION }}
      - run: npm ci && npm run tauri build -- --no-bundle           # your own Tauri build
      # … download msedgedriver.exe matching the installed WebView2 version into $PWD …
      - run: leera-qa-runner config set tauri.native_driver_path "$PWD\msedgedriver.exe"
        shell: pwsh
      - run: >-
          leera-qa-runner ci --platform tauri --environment staging
          --build src-tauri/target/release/my-app.exe
          --junit qa-results/junit.xml
        env:
          RUNNER_URL: ${{ secrets.RUNNER_URL }}
          RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
```

Cache `~/.cargo/bin` (keyed on the `tauri-driver` version) to skip the
`cargo install` on later runs. Tauri runs record no video; `--video` has no
effect for them.

### Native Windows and macOS apps in CI

**Best effort.** Native app tests need an interactive desktop and, on macOS,
privacy permissions that are granted by hand, which hosted CI machines do not
always provide. A self-hosted CI machine (a logged-in, unlocked Mac or Windows
PC with the runner's [prerequisites](test-runners.md#windows-apps) in place) is
the dependable option; hosted machines work as described below or not at all.

On **Windows** (GitHub's `windows-latest`), install WinAppDriver 1.2.1 and turn
on Developer Mode in the job. Hosted Windows machines run jobs elevated in an
interactive session, so the runner can install WinAppDriver itself:

```yaml
  qa-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm install -g @leera/qa-runner@${{ env.LEERA_QA_RUNNER_VERSION }}
      # Developer Mode (a registry value; fine on a throwaway CI machine)
      - run: reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1
        shell: cmd
      # Downloads WinAppDriver 1.2.1 (SHA-256 checked) and installs it silently
      - run: leera-qa-runner setup windows --install
      - run: npm ci && npm run build:win          # your own build: a zip of the app folder or a portable .exe
      - run: >-
          leera-qa-runner ci --platform windows --environment staging
          --build dist/MyApp-win-x64.zip
          --junit qa-results/junit.xml
        env:
          RUNNER_URL: ${{ secrets.RUNNER_URL }}
          RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
```

On **macOS** (GitHub's `macos-15`), select Xcode and run `setup macos` before
`ci`. Hosted Mac images come with a logged-in session, but whether the runner
is granted **Accessibility** there depends on the image's privacy (TCC)
database, which you cannot change from the job: when it is not granted, every
job fails at its first action or is blocked. Treat a hosted macOS job as
optional (for example `continue-on-error: true`) until it has passed on your
image:

```yaml
  qa-macos:
    runs-on: macos-15
    continue-on-error: true      # hosted runners may not grant Accessibility
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: sudo xcode-select -s /Applications/Xcode.app
      - run: npm install -g @leera/qa-runner@${{ env.LEERA_QA_RUNNER_VERSION }}
      - run: leera-qa-runner setup macos
      - run: xcodebuild -scheme MyApp -configuration Release -derivedDataPath build && ditto -c -k --keepParent build/Build/Products/Release/MyApp.app MyApp.zip
      - run: >-
          leera-qa-runner ci --platform macos --environment staging
          --build MyApp.zip
          --junit qa-results/junit.xml
        env:
          RUNNER_URL: ${{ secrets.RUNNER_URL }}
          RUNNER_TOKEN: ${{ secrets.RUNNER_TOKEN }}
```

Video needs `ffmpeg` on the machine (and, on macOS, Screen Recording
permission); without it `--video` has no effect for these platforms.

### Other CI systems

Any CI that can run Node 22.12 or newer works the same way: install
`@leera/qa-runner` at your instance's version, run the platform's `setup`
command (none for Electron; the WebDriver pieces above for Tauri; `setup windows`
or `setup macos` for native apps), and run `leera-qa-runner ci` with `RUNNER_URL` and
`RUNNER_TOKEN` in the environment. Keep the CI job's own time limit above `--timeout`, so the
command can cancel the run and write its reports before the CI system stops it.
The Docker image (`ghcr.io/leera-app/leera-qa-runner`) runs web jobs only; it
never takes Electron, Tauri, Windows or macOS app jobs.

---

## Known limitations

- **Local-build jobs of a lost CI runner stay queued.** Jobs of a local build
  are pinned to the runner of the `ci` command that created them. If that runner
  goes offline and is deleted an hour later while jobs are still queued, no other
  runner can claim them: they stay queued until the `ci` command's `--timeout`
  cancels the run (or, when the pipeline job itself is gone, until someone
  cancels the run in the app).
- **Real iOS devices** are not available on hosted CI machines; iOS runs in CI
  use simulators and a simulator build.
- **Android emulators need KVM** on Linux CI machines (the template enables
  it).
- **Electron on Linux CI machines needs Xvfb** installed (or a display), plus
  the system libraries the app itself needs.
- **Tauri runs only on Linux and Windows CI machines.** macOS machines (hosted
  or not) cannot test ordinary Tauri builds; see
  [Tauri on macOS](test-runners.md#tauri-on-macos). On Windows the
  `msedgedriver` version must match WebView2.
- **Native Windows and macOS apps in CI are best effort.** They need an
  interactive, unlocked desktop; on hosted macOS machines the runner may not be
  granted Accessibility permission, and then no macOS app job can pass. See
  [Native Windows and macOS apps in CI](#native-windows-and-macos-apps-in-ci).
