# LLDB commands

XRay includes an optional LLDB adapter for inspecting a UIKit app while its process is stopped. It adds one `xray` command with four subcommands:

```text
xray show
xray hide
xray tree
xray capture [--output PATH] [--open]
```

`show` adds the overlay, `hide` removes it, and `tree` prints the current hierarchy description, up to one MiB of text. `capture` asks the app for a PNG and copies at most 64 MiB from target memory to the Mac. Without `--output`, it creates a unique `xray-*.png` file in the Mac's temporary directory. An explicit output path must have an existing parent directory and must not already exist. `--open` opens the completed host file with macOS `open`; it never invokes a shell and has a five-second timeout.

## Install XRay in the Debug build

Add the XRay package product to the app target that you debug. The adapter talks to the Objective-C runtime class `XRayDebugBridge`, which XRay exposes only in Debug builds. If the class cannot be found, confirm that the package is linked into the selected app target and that the active scheme uses a Debug configuration.

Import the adapter from an LLDB prompt:

```lldb
command script import "/absolute/path/to/XRay/Tools/xray_lldb.py"
```

Keep the quotes when the path contains spaces.

This registers all four subcommands through one script import. Import it for the current debugging session or add the import in an Xcode breakpoint action if desired. XRay does not edit `~/.lldbinit`.

## Use

Attach or launch the app under LLDB and pause it before running a command. The adapter requires a valid stopped process and a uniquely identified main thread with a valid frame. It evaluates the Objective-C bridge on that frame with a five-second timeout. It will report an error instead of guessing a thread, dispatching synchronously to the main queue, pausing a running process, or resuming it.

For example:

```lldb
(lldb) xray show
(lldb) continue
```

The overlay is installed while the process is stopped, but UIKit cannot redraw until execution continues. `show` and `hide` therefore remind you to resume explicitly. Pause again before issuing another `xray` command.

To print the hierarchy or save a capture:

```lldb
(lldb) xray tree
(lldb) xray capture
(lldb) xray capture --output /tmp/login-screen.png --open
```

The capture transfer uses LLDB's process-memory API, so it does not depend on the Simulator filesystem. The implementation uses the same path for a Simulator process and a connected-device process. Simulator validation covered script import, hierarchy output, a 1,206 by 2,622 PNG transfer, and a visible overlay after `show` followed by an explicit resume. `hide` returned success, although its redraw could not be isolated in that example because taking verification screenshots activates XRay again. Connected-device transfer remains unverified until it is tested with the relevant Xcode, iOS, and device combination.

## Troubleshooting

- **`XRayDebugBridge is unavailable`**: link XRay into the app's Debug build and verify that dead-code stripping has not removed the package from the running target.
- **`the attached process must be stopped`**: pause in Xcode, set a breakpoint, or use LLDB's `process interrupt`, then retry. The command does not interrupt or resume the process for you.
- **`could not safely identify the main thread`**: stop again at a point where LLDB reports the `com.apple.main-thread` queue. Use `thread list` to inspect what LLDB knows; the adapter deliberately does not fall back to a numeric thread index.
- **expression timeout or evaluation failure**: ensure the app is stopped in normal executable code rather than during process teardown, then retry. The bridge returns status text and exposes `lastError`; the adapter reports these errors without throwing into the app.
- **capture output already exists**: choose a new path or omit `--output` to get a unique temporary filename. The adapter refuses to overwrite an existing file.

The bridge resolves one foreground-active, normal-level key content window. If no such window exists, or more than one qualifies, the bridge returns a clear error rather than choosing arbitrarily. This is useful for multi-scene apps: bring exactly one scene to the foreground before pausing. XRay's bridge and overlay are unavailable in Release builds.
