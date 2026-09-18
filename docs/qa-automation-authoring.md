# Authoring automated test cases

An automated test case in Leera is an ordinary manual test case with a
**script** attached — one per platform. The script says, step by step, what a
runner should do in the browser or in the app and what it should check. People
keep reading and running the case by hand; a [test runner](test-runners.md)
replays the script and records a result for every step.

You do not write scripts in the app. Your AI coding agent writes them over
**MCP**: it reads the case, explores the application (for Android, iOS,
Electron, Tauri, Windows and macOS apps, on a device, simulator or runner
machine through a [device session](#device-sessions)), drafts a script,
validates it, saves it, queues a run and reads back the failures. This page
describes the script format and that loop.

| Platform | Scripts |
|---|---|
| Web | Version 1, or version 2 with `"platform": "web"` |
| Android | Version 2 with `"platform": "android"` |
| iOS | Version 2 with `"platform": "ios"` |
| Electron | Version 2 with `"platform": "electron"` |
| Tauri | Version 2 with `"platform": "tauri"` |
| Windows apps | Version 2 with `"platform": "windows"` |
| macOS apps | Version 2 with `"platform": "macos"` |

---

## Connect an MCP client

1. In the app, open **Workspace settings → AI Clients**. Create a token, choose
   the permissions it grants, and copy the ready-made setup for your client
   (Claude Code, Cursor, Claude Desktop, ChatGPT, Grok, or any MCP client that
   speaks Streamable HTTP and can send a header). The server URL is
   `https://<your-host>/mcp`.
2. Include the QA permissions. Queueing a run whose cases sign in, or starting a
   device session with a QA credential, also needs the permission that reveals
   QA credentials, because the runner receives those accounts' passwords.
3. Check the connection by asking the agent to list your projects.

The QA automation tools the agent then sees:

| Tool | Purpose |
|---|---|
| `workspace_get_test_automation` | The case's numbered steps, its script for a platform (`platform`, default web), which platforms have scripts, and the format guide for that platform |
| `workspace_validate_test_automation` | Check a draft script against the case without saving; returns the platform, the first error, the steps left manual, and whether it signs in |
| `workspace_save_test_automation` | Save a script (its platform is inside it), or `null` with `platform` to remove that platform's script |
| `workspace_list_test_runner_pools` | Pools with their online runners, platforms, online devices and queued jobs |
| `workspace_list_test_devices` | Online runners' devices (optionally for one pool or platform), and whether each is busy |
| `workspace_list_app_builds` | A project's uploaded app builds |
| `workspace_start_device_session` | Start an interactive session on a device ([below](#device-sessions)) |
| `workspace_device_session_snapshot` | Screenshot and element tree of the session's current screen |
| `workspace_device_session_action` | Run one action in the session; returns the new screen and the action to save |
| `workspace_end_device_session` / `workspace_list_device_sessions` | End a session; list sessions |
| `workspace_get_test_run_credential_plan` | Which account each sign-in role will use in a run, and which cases would be skipped |
| `workspace_start_test_run` | Create a run; `platform` chooses web, android, ios, electron, tauri, windows or macos |
| `workspace_queue_test_automation` | Queue a run's pending cases that have a script for the run's platform, optionally with a build, a device and video |
| `workspace_list_test_automation_jobs` | Job status, platform, device, build, verdicts and failed steps with the reason |
| `workspace_get_test_run_item_debug` | A case's per-step debug log: console, page and network errors for web; device log lines and crashes for Android and iOS; as for web on Electron |
| `workspace_cancel_test_automation` | Cancel a run's queued and running jobs, or one job |

MCP clients list the tools with the `workspace_` prefix. The server also accepts
the same names with a `leera_` prefix (as older client configurations and the
server's own design documents use them); both reach the same tools.

### Setting a test runner up

Scripts only run once a machine is connected to a pool, and the agent can do
that itself on the machine it is running on:

| Tool | Purpose |
|---|---|
| `workspace_get_runner_install` | The install command for each operating system, the CLI's name, the matching version, the docs links, the pools to join, and what each platform needs installed first |
| `workspace_create_test_runner_token` | Mint a pool token, with the connect command to use it. Workspace administrators only; shown once |
| `workspace_list_test_runners` | The connected machines with their devices, and each one's setup report: which checks pass, which fail, and the fix command for the ones that do not |

Call `workspace_get_runner_install` before advising on runners rather than
repeating commands from memory — a self-hosted instance's URLs, CLI name and
docs links may point at its own mirrors. A minted token lets a machine claim
jobs and receive the test accounts' passwords, so pass it to the CLI through
`--token-stdin`, never echo or store it, and never commit it.

`workspace_queue_test_automation` returns a `hint` naming
`workspace_get_runner_install` when it queues jobs that no online runner in the
pool can claim — which is what to read when a run is queued and nothing starts.

The **Copy agent prompt** button on the Test runners page hands you a
ready-made prompt for exactly this. See
[test-runners.md](test-runners.md#set-a-runner-up-with-a-coding-agent).

---

## Script format

### Version 2

```json
{
  "version": 2,
  "platform": "android",
  "steps": [
    {
      "index": 0,
      "actions": [
        { "type": "launch" },
        { "type": "type", "target": { "id": "email" }, "value": "{{credential.username}}" },
        { "type": "type", "target": { "id": "password" }, "value": "{{credential.password}}" },
        { "type": "tap", "target": { "desc": "Sign in" } }
      ]
    },
    {
      "index": 1,
      "actions": [
        { "type": "expect_visible", "target": { "text": "Dashboard", "exact": true } }
      ]
    }
  ]
}
```

- `version` is `2` and `platform` is required: `web`, `android`, `ios`,
  `electron`, `tauri`, `windows` or `macos`. (`linux` is reserved; saving
  such a script is refused with "linux automation is not available yet".)
- `version: 1` stays valid and always means web (it may not name any other
  platform). The [web actions](#web-actions) apply to both versions.
- `steps` is a non-empty list. Each entry automates one step of the case:
  `index` is the step's **0-based position** in the case (shared steps already
  expanded — `get_test_automation` returns the numbered list), and `actions`
  run in order. Each index may appear once.
- A step with no entry is left for a person to execute.
- A script holds at most 300 actions in total. Text fields are at most 2000
  characters. Unknown fields are rejected.
- Every action may also carry a `description` (shown in results) and
  `timeout_ms` (100–120000; the runner's default is 15 s).
- A case has at most one script per platform. Saving an Android script leaves
  the web script alone.

### Shared actions

Available on every platform:

| Action | Fields | Does |
|---|---|---|
| `wait_for` | `target` | Waits until the element is visible |
| `wait` | `ms` | Sleeps, at most 30000 ms. Prefer `wait_for` or an `expect_*` |
| `expect_visible` | `target` | Passes when the element becomes visible in time |
| `expect_hidden` | `target` | Passes when the element is hidden or absent |
| `expect_text` | `target`, `value`, `match?` | Checks the element's text |
| `screenshot` | `name?` | Attaches a screenshot to the step |

`match` is `contains` (default) or `equals`.

### Targets

A target names **exactly one** locator of its platform. Optional on any target:

- `exact` — whole-string match (see each locator for its default).
- `nth` — pick the n-th match (0-based, at most 1000) when several elements
  match.
- `fallbacks` — up to 5 alternative targets, tried in order when the main one
  finds nothing (fallbacks cannot have fallbacks of their own).

### Placeholders

| Placeholder | Value | Platforms |
|---|---|---|
| `{{env.base_url}}` | The base URL of the run's test environment (may be empty for desktop apps) | all |
| `{{app.id}}` | The app's package name (Android), bundle id (iOS, macOS), app id (Electron and Tauri, optional) or AppUserModelID or executable name (Windows) from the environment, e.g. `com.example.app` | android, ios, electron, tauri, windows, macos |
| `{{credential.username}}` | Username of the QA credential the run uses for the case's role | all |
| `{{credential.password}}` | Its password. **Only allowed as the `value` of `fill` (web, Electron, Tauri) or `type` (Android, iOS, Windows, macOS)**, so it can never end up in a URL, an assertion message or a log | all |
| `{{random.email}}` | A random address, the same everywhere within one job | all |
| `{{random.string}}` | A random 12-character string, stable within a job | all |
| `{{random.number}}` | A random 6-digit number, stable within a job | all |
| `{{run.id}}` | The test run's id | all |

A script that uses `{{credential.*}}` **signs in**: the case needs a sign-in
role, and that role needs an account with a password — one for the run's
environment, or one not tied to an environment — or the case is skipped when
queued.

---

## Web actions

| Action | Fields | Does |
|---|---|---|
| `goto` | `url` | Opens a URL. It must start with `{{env.base_url}}`, `/` (relative to the environment's base URL) or `http(s)://` |
| `click` | `target` | Clicks the element |
| `hover` | `target` | Hovers over it |
| `check` / `uncheck` | `target` | Sets a checkbox or radio |
| `fill` | `target`, `value` | Replaces the text of an input |
| `select_option` | `target`, `value` | Picks an option of a `<select>` |
| `press` | `key`, `target?` | Presses a key (`Enter`, `Tab`, `Control+A`…) on the element, or on the page when `target` is omitted |
| `expect_url` | `value`, `match?` | Checks the page URL |
| `expect_title` | `value`, `match?` | Checks the page title |

plus the [shared actions](#shared-actions).

### Web targets

| Locator | Example | Matches |
|---|---|---|
| `role` (+ optional `name`) | `{"role": "button", "name": "Save"}` | ARIA role and accessible name. `role` is lowercase, e.g. `button`, `textbox`, `link`, `heading`, `checkbox` |
| `label` | `{"label": "Email"}` | Form control by its label |
| `placeholder` | `{"placeholder": "Search"}` | Input by placeholder |
| `text` | `{"text": "Welcome back"}` | Element by visible text |
| `test_id` | `{"test_id": "save-button"}` | `data-testid` |
| `css` | `{"css": "form .error"}` | CSS selector — last resort |

`exact: true` makes the name, label or text match whole and case-sensitive.
Prefer `role`, `label` and `test_id`: they survive restyling and describe what a
user sees. Use `css` only when nothing else identifies the element.

---

## Android actions

| Action | Fields | Does |
|---|---|---|
| `launch` | `activity?` | Brings the app to the front, or starts the given activity (`.MainActivity`, `com.example.app/.MainActivity`) |
| `terminate` | — | Stops the app |
| `reset` | — | Clears the app's data and launches it again |
| `deep_link` | `url` | Opens a link in the app. It must start with `{{env.base_url}}`, `http(s)://` or an app scheme such as `myapp://` (a lowercase letter, then letters, digits, `+`, `.` or `-`; not `javascript`, `file`, `data` or `blob`) |
| `tap` | `target` | Taps the element |
| `double_tap` | `target` | Double-taps it |
| `long_press` | `target`, `ms?` | Presses and holds, 300–10000 ms |
| `type` | `target`, `value`, `clear?` | Types into a field; `clear: true` empties it first |
| `clear` | `target` | Empties a field |
| `press` | `key` | Presses a device key (below) |
| `hide_keyboard` | — | Closes the on-screen keyboard |
| `swipe` | `direction`, `target?`, `distance?` | Swipes `up`, `down`, `left` or `right`, on the element or the screen; `distance` is a fraction of it, 0.1–1 |
| `scroll_to` | `target`, `direction?`, `max_swipes?` | Swipes until the element is visible: `direction` defaults to `down`, `max_swipes` (1–20) to 10 |
| `set_orientation` | `value` | `portrait` or `landscape` |
| `accept_alert` / `dismiss_alert` | — | Answers a system dialog, e.g. a permission prompt |

plus the [shared actions](#shared-actions). Web actions are refused with a hint,
e.g. `automation.steps[0].actions[0].type 'goto' is not an android action; use
deep_link` (`click` → `tap`, `fill` → `type`; `hover`, `expect_url` and
`expect_title` have no touch-screen equivalent).

**Keys** for `press`: `back`, `home`, `enter`, `tab`, `delete`, `volume_up`,
`volume_down`, `app_switch`, or an Android key code name `KEYCODE_<NAME>`
(e.g. `KEYCODE_SEARCH`).

### Android targets

| Locator | Example | Matches |
|---|---|---|
| `id` | `{"id": "login_button"}` | The view's resource-id. The package prefix is optional: `login_button` matches `<any package>:id/login_button`; `com.example.app:id/login_button` matches exactly |
| `desc` | `{"desc": "Sign in"}` | The content-description (accessibility label). Whole string by default; `exact: false` matches a part |
| `text` | `{"text": "Welcome"}` | Visible text. Contains by default; `exact: true` matches the whole text |
| `test_id` | `{"test_id": "login-button"}` | A React Native or Expo `testID`: the resource-id equal to it, then `<package>:id/<value>`, then the content-description |
| `class` | `{"class": "android.widget.EditText"}` | The widget class, full or simple name (`EditText`); usually with `nth` |
| `uiautomator` | `{"uiautomator": "new UiSelector().checkable(true)"}` | A UiSelector expression, at most 500 characters |
| `xpath` | `{"xpath": "//android.widget.Button[2]"}` | XPath over the page source, at most 500 characters — last resort |

### Choosing locators

- **Prefer `desc` and `id`.** They are what a snapshot suggests first and they
  survive layout and copy changes. Add a content description or a view id in the
  app's code where an element has neither.
- **React Native and Expo:** give elements a `testID` and use `test_id`, which
  tries both the resource-id and the content description the `testID` can end
  up in.
- **Jetpack Compose:** set `Modifier.testTag(...)` with
  `testTagsAsResourceId = true` so the tag becomes a resource-id, or give the
  element a `contentDescription`.
- Use `text` for labels a user reads and that the test should check, with
  `exact: true` when a longer text could also match.
- Avoid `class` + `nth`, `uiautomator` and `xpath` where anything else works:
  they break when the layout changes. Snapshots mark such suggestions as
  *fragile*.

### App state and builds

- **Every job starts clean.** Before the script runs, the runner installs the
  build (when the environment uses one), clears the app's data and launches it.
  Start the first step with `launch {}` anyway, so the script also says where it
  begins.
- Use `reset {}` inside a script when a later step needs a fresh start (for
  example to see first-launch onboarding again).
- Which app and build a run uses is set on the **test environment** (package
  id, launch activity, default build or *already installed*), and a run can be
  queued with a specific build. See [App builds](test-runners.md#app-builds)
  and [Configure the app on a test environment](test-runners.md#configure-the-app-on-a-test-environment).
- Deep links jump straight to a screen: `{"type": "deep_link", "url":
  "myapp://orders/{{run.id}}"}`. The app must declare the scheme.

---

## iOS actions

The same touch actions as [Android](#android-actions), except:

| Action | Fields | Does |
|---|---|---|
| `launch` | — | Brings the app to the front, or starts it. There is no `activity` |
| `reset` | — | Reinstalls the app from the run's build; for an app that is *already installed on the runner*, clears its data on a simulator (blocked on a real device) |
| `hide_keyboard` | — | **Not available.** Use `press {"key": "return"}` or tap outside the field |

Everything else works as on Android: `terminate`, `deep_link`, `tap`,
`double_tap`, `long_press`, `type`, `clear`, `press`, `swipe`, `scroll_to`,
`set_orientation`, `accept_alert`, `dismiss_alert`, plus the
[shared actions](#shared-actions). Web actions and `hide_keyboard` are refused
with a hint, e.g. `… 'hide_keyboard' is not an ios action; use press {key:
return}`.

**Keys** for `press`: `home`, `return`, `delete`, `volume_up`, `volume_down`.
**There is no `back` key** on iOS: tap the screen's own back button (usually
the navigation bar's first button, e.g. `{"label": "Back"}` or the previous
screen's title). `press {"key": "back"}` is refused.

### iOS targets

| Locator | Example | Matches |
|---|---|---|
| `id` | `{"id": "login_button"}` | The accessibility identifier (`accessibilityIdentifier` in UIKit, `.accessibilityIdentifier(_:)` in SwiftUI) |
| `label` | `{"label": "Sign in"}` | The accessibility label. Whole string by default; `exact: false` matches a part |
| `text` | `{"text": "Welcome"}` | An element whose label or value contains the text; `exact: true` matches the whole text |
| `test_id` | `{"test_id": "login-button"}` | A React Native or Expo `testID`; the same as `id`, since `testID` becomes the accessibility identifier on iOS |
| `type` | `{"type": "textfield", "nth": 1}` | The element type: `button`, `textfield`, `securetextfield`, `statictext`, `cell`, `switch`, `image` or `other`; usually with `nth` |
| `predicate` | `{"predicate": "label BEGINSWITH 'Order'"}` | An `NSPredicate` string over element attributes, at most 500 characters |
| `class_chain` | `` {"class_chain": "**/XCUIElementTypeCell[`name == 'row'`]"} `` | An XCUITest class chain, at most 500 characters |
| `xpath` | `{"xpath": "//XCUIElementTypeButton[2]"}` | XPath over the page source, at most 500 characters — last resort (slow on iOS) |

Android locators such as `desc`, `class` and `uiautomator` are refused on iOS.

### Choosing iOS locators

- **Prefer `id`.** Snapshots suggest `id` first, then `label`, then `text`,
  then a class chain, and XPath last. An accessibility identifier is not shown
  to users or read by VoiceOver, so it survives copy changes and localisation.
  Add one in the app's code where an element has none:
  - UIKit: `button.accessibilityIdentifier = "login_button"`
  - SwiftUI: `.accessibilityIdentifier("login_button")`
- **React Native and Expo:** give elements a `testID` and use `test_id` (or `id`
  with the same value). On iOS, a `testID` on a component that groups its
  children (for example a touchable wrapping text) may hide the children from
  the accessibility tree; put the `testID` on the element you want to tap.
- **Flutter:** wrap widgets in `Semantics(identifier: …)` (or `label: …`) so the
  element shows up with an identifier or label.
- Use `label` for controls identified by what VoiceOver reads, and `text` for
  words a user sees that the test should check (`exact: true` when a longer text
  could also match).
- `type` + `nth`, `predicate`, `class_chain` and `xpath` break when the layout
  changes; snapshots mark such suggestions as *fragile*.
- **Secure text fields** (`securetextfield`) are separate from text fields: a
  password field is not matched by `{"type": "textfield"}`.

### iOS app state and builds

- **Every job starts clean**: the runner uninstalls the app and installs the
  run's build again before the script runs, then launches it. For an app that
  is *already installed on the runner* it only checks that the app is there.
  Start the first step with `launch {}` anyway.
- `reset {}` inside a script reinstalls the run's build. For an app that is
  already installed it clears the app's data on a simulator; on a real device
  such a step is blocked.
- The environment's iOS app names the **bundle id** (`{{app.id}}`) and whether
  a build is installed or the app is already on the device.
- **Simulators need a simulator build** (a zipped `.app` built with
  `-sdk iphonesimulator`), **real devices an `.ipa`** signed for your team; the
  wrong kind is blocked. See [iOS app builds](test-runners.md#ios-app-builds).
- System alerts (notifications, location, tracking permission) appear over the
  app: answer them with `accept_alert {}` / `dismiss_alert {}` in the step where
  they show up.
- Deep links need the scheme registered in the app's `Info.plist` (or an
  associated domain for `https://` links).

---

## Electron actions

Electron scripts use the [web actions](#web-actions) and
[web targets](#web-targets) on the app's windows, without `goto`, plus three
actions for the app itself:

| Action | Fields | Does |
|---|---|---|
| `launch` | `args?` | Starts the app, with up to 20 extra command-line arguments of at most 500 characters each. `{{credential.password}}` is not allowed in `args` |
| `terminate` | — | Closes the app |
| `focus_window` | `title` **or** `index` | Makes a window the one later actions work on: the first window whose title matches, or the window's 0-based number in the order the windows opened (at most 100) |

The web actions work as in a browser, on the focused window: `click`, `hover`,
`check`, `uncheck`, `fill`, `select_option`, `press` (`Enter`, `Control+S`…),
`expect_url` and `expect_title` (they read the focused window's URL and title),
plus the [shared actions](#shared-actions). `goto` is refused: an Electron app
decides what it loads. Targets are the web locators (`role` + `name`, `label`,
`placeholder`, `text`, `test_id`, `css`); prefer `role`, `label` and `test_id`
as for web.

### Electron example

```json
{
  "version": 2,
  "platform": "electron",
  "steps": [
    {
      "index": 0,
      "actions": [
        { "type": "launch", "args": ["--lang=en"] },
        { "type": "expect_visible", "target": { "role": "heading", "name": "Sign in" }, "timeout_ms": 30000 }
      ]
    },
    {
      "index": 1,
      "actions": [
        { "type": "fill", "target": { "label": "Email" }, "value": "{{credential.username}}" },
        { "type": "fill", "target": { "label": "Password" }, "value": "{{credential.password}}" },
        { "type": "click", "target": { "role": "button", "name": "Sign in" } }
      ]
    },
    {
      "index": 2,
      "actions": [
        { "type": "click", "target": { "role": "menuitem", "name": "Preferences" } },
        { "type": "focus_window", "title": "Preferences" },
        { "type": "expect_visible", "target": { "test_id": "preferences-form" } }
      ]
    }
  ]
}
```

### Electron app state and builds

- **Start the first step with `launch {}`**, so every run begins from a freshly
  started app. `terminate {}` followed by `launch {}` restarts it within a
  script.
- **Windows.** Actions work on the focused window, which is the app's first
  window after `launch`. When an action opens another window (preferences, an
  about box, a second document), add `focus_window` before acting on it, and
  again to go back.
- Which app a run uses is set on the **test environment**: an uploaded build
  (`.zip`, `.AppImage`, portable `.exe` or `.dmg`), optionally with the
  executable inside it, or a path on the runner. See
  [Electron](test-runners.md#electron).
- When a case needs the app without data from earlier runs on the same
  machine, have the app accept an argument for its data directory and pass a
  unique one with `launch`, e.g.
  `"args": ["--data-dir=/tmp/qa-{{run.id}}-{{random.string}}"]`.

---

## Tauri actions

Tauri scripts use the same actions as [Electron](#electron-actions): the
[web actions](#web-actions) without `goto` (`click`, `hover`, `check`,
`uncheck`, `fill`, `select_option`, `press`, `expect_url`, `expect_title`),
`launch {args?}`, `terminate {}`, `focus_window {title | index}`, and the
[shared actions](#shared-actions). They run on Linux and Windows runners, and on
a Mac only for builds with the embedded WebDriver plugin (see
[Tauri](test-runners.md#tauri)).

### Tauri targets

A Tauri app is driven over WebDriver, which has no accessibility-tree queries,
so a target names exactly one of four locators:

| Locator | Example | Matches |
|---|---|---|
| `test_id` | `{"test_id": "save-button"}` | The `data-testid` attribute |
| `css` | `{"css": "#settings-form"}` | CSS selector |
| `text` | `{"text": "Welcome back", "exact": true}` | Element by visible text |
| `xpath` | `{"xpath": "//nav//a[2]"}` | XPath, at most 500 characters |

`exact`, `nth` and `fallbacks` work as on other platforms. `role`, `label` and
`placeholder` are refused, e.g. `automation.steps[0].actions[1].target.role is not a tauri
locator; use css, text, test_id or xpath`; so are Android and iOS locators such
as `id`.

**Prefer `test_id`.** Add `data-testid` to the elements your tests use; it is
the one locator that survives restyling and copy changes. Then `css` with an
id, then `text` with `exact: true`; use `xpath` only when nothing else works.
Snapshots in a [device session](#device-sessions) suggest targets in that
order.

### Tauri example

```json
{
  "version": 2,
  "platform": "tauri",
  "steps": [
    {
      "index": 0,
      "actions": [
        { "type": "launch" },
        { "type": "expect_visible", "target": { "test_id": "sign-in-form" }, "timeout_ms": 30000 }
      ]
    },
    {
      "index": 1,
      "actions": [
        { "type": "fill", "target": { "test_id": "email" }, "value": "{{credential.username}}" },
        { "type": "fill", "target": { "test_id": "password" }, "value": "{{credential.password}}" },
        { "type": "click", "target": { "css": "#sign-in" } }
      ]
    },
    {
      "index": 2,
      "actions": [
        { "type": "expect_text", "target": { "test_id": "account-name" }, "value": "{{credential.username}}" },
        { "type": "click", "target": { "text": "Preferences", "exact": true } },
        { "type": "focus_window", "title": "Preferences" },
        { "type": "expect_visible", "target": { "test_id": "preferences-form" } }
      ]
    }
  ]
}
```

### What to test with Tauri jobs

A Tauri app's interface is a web page, and most of its behaviour can be tested
more cheaply as one. When the same interface also runs in a browser (or its
frontend can be served on its own):

- **Cover functionality with web tests**: forms, navigation, validation, the
  data shown. They run on every runner, including Docker and macOS, with richer
  targets (`role`, `label`), video and a browser debug log.
- **Use Tauri jobs for what only the packaged app does**: the app starts from
  its build, calls into the Rust side work, windows open and take focus,
  settings and files persist between launches, and each operating system's
  build behaves the same.

Tauri runs record no video, and elements outside the web view (native menus,
file dialogs, notifications, the tray) cannot be reached from a script.

### Tauri app state and builds

- **Start the first step with `launch {}`**; `terminate {}` then `launch {}`
  restarts the app within a script.
- **Windows** work as for Electron: add `focus_window` before acting on a
  window the app opened.
- The run's app is set on the **test environment**: an uploaded build (a `.zip`
  of the app folder, an `.AppImage`, the portable `.exe`, or on a Mac a plugin
  build as a zipped `.app` or `.dmg`), optionally with the executable inside
  it, or a path on the runner. Installers (`.msi`) and packages (`.deb`) are
  refused. See [Tauri app builds](test-runners.md#tauri-app-builds).
- For a clean start without data from earlier runs, pass a unique data
  directory with `launch`, as for [Electron](#electron-app-state-and-builds).

---

## Windows and macOS actions

Native Windows and macOS apps share one set of actions. They drive the app's
real controls through the operating system's accessibility layer (UI Automation
on Windows, the accessibility API on macOS), so there are no web actions, no
URLs and no touch gestures. They run on Windows and Mac runners with the
driver set up (see [Windows apps](test-runners.md#windows-apps) and
[macOS apps](test-runners.md#macos-apps)).

| Action | Fields | Does |
|---|---|---|
| `launch` | `args?` | Starts the app, with up to 20 extra command-line arguments of at most 500 characters each; a later `launch` restarts it. `{{credential.password}}` is not allowed in `args` |
| `terminate` | — | Closes (Windows) or quits (macOS) the app |
| `focus_window` | `title` | Makes the app's window with that title the one later actions work on: dialogs, sheets and second windows |
| `click` | `target` | Clicks the element |
| `double_click` | `target` | Double-clicks it |
| `right_click` | `target` | Right-clicks it, e.g. to open a context menu |
| `hover` | `target` | Moves the pointer over it |
| `type` | `target`, `value`, `clear?` | Types into a field; `clear: true` empties it first |
| `clear` | `target` | Empties a field |
| `press` | `key`, `target?` | Presses a key or a key chord (below), on the element when a target is given |
| `check` / `uncheck` | `target` | Sets a checkbox (or toggle) on or off |
| `select_option` | `target`, `value` | Picks the entry named `value` in a combo box or pop-up button |

plus the [shared actions](#shared-actions). There is no `index` form of
`focus_window`: use the window's title. Actions of other platforms are refused
with a hint, e.g. `automation.steps[0].actions[1].type 'fill' is not a windows
action; use type` (`tap` → `click`, `double_tap` → `double_click`,
`long_press` → `right_click`, `goto` and `deep_link` → `launch`;
`expect_url` and `expect_title` have no equivalent: check something the window
shows).

**Keys** for `press`: a lowercase letter, a digit, `f1`–`f12`, or `enter`,
`return`, `tab`, `escape`, `backspace`, `delete`, `space`, `up`, `down`,
`left`, `right`, `home`, `end`, `page_up`, `page_down`, `insert` — optionally
after any of the modifiers `ctrl+`, `alt+`, `shift+` and `cmd+`, each at most
once: `ctrl+s`, `ctrl+shift+n`, `alt+f4`, `cmd+s`, `cmd+shift+z`. Use `ctrl+`
for Windows shortcuts and `cmd+` for macOS ones (`alt+` is the Option key on a
Mac). Anything else is refused, e.g. `… key 'Control+S' is not a windows key;
use a letter, digit, f1-f12 or …`.

`{{credential.password}}` is allowed only as the `value` of `type`.
`{{app.id}}` is the environment's App ID: the AppUserModelID or executable name
on Windows, the bundle id on macOS.

### Windows targets

| Locator | Example | Matches |
|---|---|---|
| `automation_id` | `{"automation_id": "SaveButton"}` | The UI Automation `AutomationId` |
| `name` | `{"name": "Save"}` | The element's `Name`, usually its visible label or accessible name |
| `class_name` | `{"class_name": "Edit"}` | The `ClassName` (Win32 window class or framework type); usually with `nth` |
| `control_type` | `{"control_type": "Button", "nth": 2}` | The UI Automation control type; usually with `nth` |
| `xpath` | `{"xpath": "//Window/Pane/Button[@Name='OK']"}` | XPath over the UI Automation tree, at most 500 characters — last resort |

`control_type` is one of `Button`, `Edit`, `Text`, `CheckBox`, `ComboBox`,
`List`, `ListItem`, `MenuItem`, `Tab`, `TabItem`, `Tree`, `TreeItem`, `Window`,
`Pane`, `Document`, `Hyperlink`, `Image`, `RadioButton`, `Slider`, `Spinner`,
`ToolBar`, `DataGrid`, `DataItem` or `Custom` (with that capitalisation).
`exact`, `nth` and `fallbacks` work as on other platforms.

### macOS targets

| Locator | Example | Matches |
|---|---|---|
| `identifier` | `{"identifier": "saveButton"}` | The accessibility identifier |
| `title` | `{"title": "Save"}` | The element's title or label |
| `role` | `{"role": "AXTextArea"}` | The accessibility role; usually with `nth` |
| `predicate` | `{"predicate": "elementType == 9 AND title BEGINSWITH 'Save'"}` | An `NSPredicate` string over the element's attributes (`identifier`, `title`, `label`, `value`, `elementType`…), at most 500 characters |
| `class_chain` | `` {"class_chain": "**/XCUIElementTypeWindow/**/XCUIElementTypeButton[`title == 'Save'`]"} `` | An XCTest class chain, at most 500 characters |

`role` must be an accessibility role name: `AX` followed by letters, e.g.
`AXButton`, `AXTextField`, `AXTextArea`, `AXStaticText`, `AXCheckBox`,
`AXRadioButton`, `AXPopUpButton`, `AXMenuItem`, `AXMenuBarItem`, `AXTable`,
`AXRow`, `AXCell`, `AXWindow`, `AXSheet`, `AXGroup`. There is no `xpath` on
macOS. `exact`, `nth` and `fallbacks` work as on other platforms.

### Choosing Windows and macOS locators

- **Give the controls your tests use a stable identifier in the app**, then
  target it:
  - **Windows:** set the AutomationId — `AutomationProperties.AutomationId` in
    WPF, UWP and WinUI XAML; the control's `Name` property in WinForms (it
    becomes the AutomationId); the control id for Win32 dialogs.
  - **macOS:** set the accessibility identifier —
    `.accessibilityIdentifier("save")` in SwiftUI,
    `button.setAccessibilityIdentifier("save")` (or the *Identifier* field in
    Interface Builder's Identity inspector) in AppKit.
- **Then the visible name**: `name` on Windows, `title` on macOS, for labels a
  user reads and that rarely change.
- **`control_type` / `role` with `nth`** for controls that have neither, such
  as the only text area of a window.
- **`xpath` (Windows), `predicate` and `class_chain` (macOS) last.** They break
  when the window's layout changes.

Snapshots in a [device session](#device-sessions) suggest targets in that
order: `automation_id`, `name`, then `control_type` with `nth` on Windows;
`identifier`, `title`, then `role` with `nth` on macOS; `xpath` last.

### Windows example (Notepad)

With a Windows app on the environment whose App ID is `notepad.exe` and App
source *Already installed on the runner*:

```json
{
  "version": 2,
  "platform": "windows",
  "steps": [
    {
      "index": 0,
      "actions": [
        { "type": "launch" },
        {
          "type": "wait_for",
          "target": { "control_type": "Document", "fallbacks": [{ "class_name": "Edit" }] },
          "timeout_ms": 30000
        }
      ]
    },
    {
      "index": 1,
      "actions": [
        {
          "type": "type",
          "target": { "control_type": "Document", "fallbacks": [{ "class_name": "Edit" }] },
          "value": "Order {{random.number}}"
        },
        {
          "type": "expect_text",
          "target": { "control_type": "Document", "fallbacks": [{ "class_name": "Edit" }] },
          "value": "Order "
        }
      ]
    },
    {
      "index": 2,
      "actions": [
        { "type": "press", "key": "ctrl+a" },
        { "type": "press", "key": "delete" },
        {
          "type": "type",
          "target": { "control_type": "Document", "fallbacks": [{ "class_name": "Edit" }] },
          "value": "Replaced"
        },
        {
          "type": "expect_text",
          "target": { "control_type": "Document", "fallbacks": [{ "class_name": "Edit" }] },
          "value": "Replaced",
          "match": "equals"
        }
      ]
    }
  ]
}
```

The example finds Notepad's editor by its control type (current Notepad) with a
class-name fallback (classic Notepad), because it is a system app you cannot
change. In your own
app, target AutomationIds instead.

### macOS example (TextEdit)

With a macOS app on the environment whose App ID is `com.apple.TextEdit` and
App source *Already installed on the runner*:

```json
{
  "version": 2,
  "platform": "macos",
  "steps": [
    {
      "index": 0,
      "actions": [
        { "type": "launch" },
        { "type": "press", "key": "cmd+n", "description": "New document (TextEdit may open with a file dialog)" },
        { "type": "wait_for", "target": { "role": "AXTextArea" }, "timeout_ms": 30000 }
      ]
    },
    {
      "index": 1,
      "actions": [
        { "type": "type", "target": { "role": "AXTextArea" }, "value": "Hello from {{run.id}}" },
        { "type": "expect_text", "target": { "role": "AXTextArea" }, "value": "Hello from" }
      ]
    },
    {
      "index": 2,
      "actions": [
        { "type": "press", "key": "cmd+z" },
        { "type": "press", "key": "cmd+shift+z" },
        { "type": "expect_text", "target": { "role": "AXTextArea" }, "value": "Hello from" }
      ]
    },
    {
      "index": 3,
      "actions": [
        { "type": "press", "key": "cmd+s" },
        { "type": "expect_visible", "target": { "role": "AXSheet" } },
        { "type": "click", "target": { "title": "Cancel", "exact": true } },
        { "type": "terminate" }
      ]
    }
  ]
}
```

### Windows and macOS app state and builds

- **Start the first step with `launch {}`**; `terminate {}` then `launch {}`
  restarts the app within a script.
- **Windows and dialogs.** Actions work on the app's main window after
  `launch`. When an action opens a dialog, a sheet or another window, add
  `focus_window {title}` before acting on it, and again to go back.
- **The app keeps its data between runs.** The runner does not reset
  settings, documents or the registry / `~/Library` data an app writes. For a
  clean start, have the app accept a data-directory argument and pass a unique
  one with `launch`, e.g. `"args": ["--data-dir", "C:\\qa\\{{run.id}}-{{random.string}}"]`.
- **The runner uses the real mouse and keyboard** of the desktop; steps that
  depend on focus (typing, key chords) go to whatever window is in front, so
  click or `focus_window` first when another window may have opened.
- Which app a run uses is set on the **test environment**: an uploaded build
  (Windows: a `.zip` of the app folder or a portable `.exe`; macOS: a zipped
  `.app` or a `.dmg`; `.msi` and `.pkg` installers are refused), a path on the
  runner, or an app already installed there, started by its App ID. See
  [Windows app builds](test-runners.md#windows-app-builds) and
  [macOS app builds](test-runners.md#macos-app-builds).

---

## Results

For each automated step the runner records:

- **passed** — every action succeeded; when the step has an `expect_*`, a
  "verified" screenshot is attached.
- **failed** — an action or check failed. The note says which action and why,
  and a failure screenshot is attached. The remaining steps are not run.
- **blocked** — the case could not be tested: the environment was unreachable,
  the device was not ready, the app build was missing or could not be installed,
  a placeholder had no value, or the job ran past its time limit.

Every step also gets a debug log — for web, console errors and warnings, page
errors and network requests; for Android, the app's logcat warnings and errors
and any crash; for iOS, the app's error and fault log lines and, on simulators,
any crash report; for Electron, as for web, from the focused window; for
Windows and macOS apps, the Appium log of failed steps — and a run can be
queued with video `off`, `on_failure` or `always` (WebM for web and Electron,
MP4 for Android, H.264 video for iOS; Windows and macOS apps only on runners
with ffmpeg; Tauri runs record no video).

---

## The authoring loop (web)

A typical session with a coding agent that has the application's source open:

1. **Pick the cases.** "Automate the login and checkout cases in project SHOP."
   The agent searches test cases and calls `get_test_automation` for each, which
   returns the numbered steps and the format guide.
2. **Find stable locators.** The agent reads the UI code for labels, roles and
   `data-testid`s (or adds test ids where there are none), and checks routes for
   `goto` URLs.
3. **Draft and validate.** It writes the script and calls
   `validate_test_automation` until `valid` is true, fixing the reported path
   (e.g. `automation.steps[1].actions[0].target needs exactly one of …`).
   `manual_steps` shows which steps are still left for a person — intended for
   steps a script cannot check.
4. **Save.** `save_test_automation`.
5. **Run it.** Create (or reuse) a test run on the right environment, check
   `get_test_run_credential_plan` when the script signs in, pick a pool with an
   online runner from `list_test_runner_pools`, and `queue_test_automation`
   (with `video: "on_failure"` while iterating).
6. **Read the results.** Poll `list_test_automation_jobs` until the jobs finish.
   For a failed step, read the note, then `get_test_run_item_debug` for console
   and network errors. Fix the script (or the application) and repeat from 3.

---

## Device sessions

For an app, reading the source is rarely enough to know what the screen really
exposes. A **device session** lets the agent look at the running app on a device
connected to one of your runners (for desktop apps, on the runner machine itself), try each action, and copy the exact targets
that worked into the script. How runners handle sessions is described in
[Test runners](test-runners.md#device-sessions).

### The loop

1. **Read the case.** `get_test_automation` with `platform: "android"` (or
   `"ios"`, `"electron"`, `"tauri"`, `"windows"`, `"macos"`) returns the steps and that platform's format guide.
2. **Start a session.** `start_device_session` with `platform: "android"`,
   `"ios"`, `"electron"`, `"tauri"`, `"windows"` or `"macos"`, the environment (`environment_id`, or `environment_slug` with
   `project_id`), and optionally `pool_id`, a `device`, a `build_id`,
   `app: "installed"`, a `credential_id` (so the session can type a real test
   account) and `idle_minutes` (at most 30). It fails at once when no online
   runner has an idle device of that platform, and otherwise waits up to 20 s
   for a runner to pick the session up. The runner installs and launches the app exactly as a job would.
3. **Look.** `device_session_snapshot` returns the screenshot as an image and
   the element tree as text, with a ref (`e1`, `e2`, …) per element. For each
   ref it also returns the `target` to use in a script, `alternatives`, and the
   element's bounds, plus the tail of the device log.
4. **Act.** `device_session_action` with an action that points at a `ref`, a
   `target`, or (for exploring only) a screen point `at: {x, y}`. Every script
   action works, plus `back` (Android only) and `home` (not on desktop apps). The
   result is the new screen and **`applied`: the concrete, validated action to put in the script**, with the
   ref replaced by its target. Coordinate taps are marked as not saveable. Refs
   belong to the last snapshot; after the screen changes, take a new one.
5. **Repeat** until the case's steps are covered, collecting the `applied`
   actions under their step indexes.
6. **Validate and save.** `validate_test_automation`, then
   `save_test_automation`.
7. **End the session** with `end_device_session` so the device is free for jobs
   (it also ends by itself after 10 idle minutes, or 60 minutes in total).
8. **Run it.** `start_test_run` with the platform (or reuse a run),
   `queue_test_automation` (optionally with `build_id`, a `device` or labels
   such as `["android-real"]` or `["ios-simulator"]`, and `video`), then `list_test_automation_jobs`,
   and `get_test_run_item_debug` for the device log and crashes of a failed step.

**Electron sessions** run on a runner machine rather than a phone: the device
is the runner's `host`, one session or job at a time per runner. The runner
starts the app as a job would. Snapshots list the focused window's elements
with web targets (`role` + `name`, `label`, `test_id`…); `tap` and `type` on a
ref come back in `applied` as `click` and `fill`. `launch`, `terminate` and
`focus_window` work in the session; `back` and `home` do not.

**Tauri sessions** work the same way on a Linux or Windows runner (or a Mac
runner with plugin builds). The element tree comes from a script the runner
ships and runs in the app's web view; each ref's `target` uses the Tauri
locators, preferring `test_id`, then `css` with an id, then exact `text`, then
`xpath`.

**Windows and macOS app sessions** also run on the runner machine (`host`),
one session or job at a time, and need the same interactive, unlocked desktop
as jobs. Snapshots list the focused window's accessibility tree; each ref's
`target` prefers `automation_id`, then `name`, then `control_type` with `nth`
(Windows) or `identifier`, then `title`, then `role` with `nth` (macOS). `tap`
on a ref comes back in `applied` as `click`. `launch`, `terminate`,
`focus_window` and `press` with chords work in the session; `back` and `home`
do not.

When an action takes longer than about 20 s, the tool returns
`status: "running"` with a `command_id`; call `device_session_snapshot` again to
collect the result. A session runs one action at a time.

### Example transcript

A condensed exchange for case **TC-12-4 "Sign in with email"** (steps: 0 open
the app, 1 sign in, 2 see the dashboard). Tool results are shortened.

```text
agent → workspace_get_test_automation {"test_case_key": "TC-12-4", "platform": "android"}
      ← steps: [0 "Open the app", 1 "Sign in with a valid account", 2 "The dashboard is shown"]
        automation: null, scripts: [{"platform": "web", …}], format: "A script is {"version": 2, …"

agent → workspace_start_device_session {"platform": "android", "environment_id": 3,
                                        "pool_id": 1, "credential_id": 8}
      ← {"session_id": 41, "status": "active",
         "device": {"id": "emulator-5554", "name": "Pixel_8_API_35", "kind": "emulator", "os_version": "15"},
         "app": {"id": "com.acme.shop", "install": "build", "build": {"id": 7, "version_name": "1.2.0"}},
         "expires_at": "…", "next": "…"}

agent → workspace_device_session_snapshot {"session_id": 41}
      ← [image: screenshot]
        screen: {"width": 1080, "height": 2400, "activity": ".LoginActivity", "package": "com.acme.shop"}
        tree:
          [e1] textfield id=email "Email" {48,420,984,140} focusable
          [e2] textfield id=password "Password" {48,600,984,140} focusable
          [e3] button "Sign in" {48,820,984,140} clickable
        refs: {"e1": {"target": {"id": "email"}, …},
               "e3": {"target": {"desc": "Sign in"}, "alternatives": [{"text": "Sign in", "exact": true}], …}}

agent → workspace_device_session_action {"session_id": 41,
          "action": {"type": "type", "ref": "e1", "value": "{{credential.username}}"}}
      ← applied: {"type": "type", "target": {"id": "email"}, "value": "{{credential.username}}"}

agent → workspace_device_session_action {"session_id": 41,
          "action": {"type": "type", "ref": "e2", "value": "{{credential.password}}"}}
      ← applied: {"type": "type", "target": {"id": "password"}, "value": "{{credential.password}}"}

agent → workspace_device_session_action {"session_id": 41, "action": {"type": "tap", "ref": "e3"}}
      ← [image: screenshot]  screen.activity: ".HomeActivity"
        tree: [e1] text "Dashboard" {48,180,600,90} …
        applied: {"type": "tap", "target": {"desc": "Sign in"}}

agent → workspace_validate_test_automation {"test_case_key": "TC-12-4", "automation": {
          "version": 2, "platform": "android", "steps": [
            {"index": 0, "actions": [{"type": "launch"}]},
            {"index": 1, "actions": [
              {"type": "type", "target": {"id": "email"}, "value": "{{credential.username}}"},
              {"type": "type", "target": {"id": "password"}, "value": "{{credential.password}}"},
              {"type": "tap", "target": {"desc": "Sign in"}}]},
            {"index": 2, "actions": [{"type": "expect_visible", "target": {"text": "Dashboard", "exact": true}}]}]}}
      ← {"valid": true, "platform": "android", "manual_steps": [], "signs_in": true}

agent → workspace_save_test_automation {"test_case_key": "TC-12-4", "automation": {…same script…}}
      ← saved; scripts now exist for android and web

agent → workspace_end_device_session {"session_id": 41}
      ← {"status": "ended"}

agent → workspace_queue_test_automation {"run_id": 19, "pool_id": 1, "video": "on_failure"}
      ← {"platform": "android", "build": {"id": 7, "version_name": "1.2.0"}, "queued": 1, …}
```

The password never appears in the conversation: the session types the
credential's value on the device, and results redact it.

### Tips

- Keep one case's actions inside the step they belong to; a failure then points
  at the right step.
- Put an `expect_*` at the end of each step that has an expected result — that
  is what turns "did not crash" into a check.
- Save the `target` from `applied` rather than writing one by hand. When a
  snapshot marks a suggestion *fragile*, add a content description or id in the
  app instead.
- Make data unique with `{{random.*}}` so runs do not collide.
- Wait on conditions (`wait_for`, `expect_visible`) rather than `wait`; give the
  first check on a screen that loads data a longer `timeout_ms`.
- Never paste real passwords into a script; use a QA credential and
  `{{credential.password}}`.
