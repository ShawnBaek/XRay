# Validation

Validation date: 6 September 2026. This is an unreleased refactor of the 1.x library.

## Deployment and toolchain

The package and example target iOS / iPadOS 17 with Swift 6. iOS 17 provides the custom UIKit traits and `UITraitBridgedEnvironmentKey` used for context propagation. Newer SDK features are not required by the implementation.

Local validation uses **Xcode 27.0 beta, build 27A5228h, Swift 6.4**. This machine has iOS 18.5 and iOS 27.0 Simulator runtimes; it does not have iOS 17 or the current stable iOS 26 runtime and Xcode 26 toolchain. Compilation with an iOS 17 deployment target checks API availability, but is not a substitute for running on iOS 17.

## Automated coverage

| Suite | Runtime | Coverage |
| --- | --- | --- |
| Package Debug | iPhone, iOS 27.0 beta | 14 passing core and SwiftUI integration tests |
| Package Debug | iPad, iPadOS 18.5 | 15 passing core, lifecycle, and UIKit → SwiftUI → UIKit integration tests |
| Package Release | iPad, iPadOS 18.5 | Inactive installation, no overlay or trait changes, no Objective-C debugger bridge, explicit capture/hierarchy disabled |
| Example | iPhone, iOS 27.0 beta | Storyboard wiring and two passing UI tests for UIKit and hosted SwiftUI captures |
| Example | iPad, iPadOS 18.5 | Both UI tests passed again after image-preview polish; SwiftUI capture contained four semantic labels |
| LLDB | iPhone, iOS 27.0 beta | Live hierarchy output, annotated PNG memory transfer, and visible show after resume; hide returned success |

The original implementation failed both added baseline regressions: repeated capture increased the descendant count from 5 to 13, and removal deleted an application-owned view using the old overlay tag. The refactored implementation passes both.

Package tests cover weak target lifetime, screenshot expiry and cancellation, repeated installation, independent windows, multiple SwiftUI installation owners, label parent IDs and geometry, inherited deep actions in both framework directions, subtree inspection, hidden and clipped content, offscreen nonclipping parents, traversal limits, transformed corners, pattern colors, extreme capture dimensions, and safe hierarchy text formatting.

The example UI tests capture real displayed content, assert SwiftUI semantic labels are present, verify repeated UIKit captures retain the same node count, and exercise screenshot activation followed by dismissal. They post Apple's screenshot notification through a Debug-only test control; a Simulator screenshot alone does not validate the physical screenshot-button gesture.

A source review identified and verified fixes for four additional issues: integer overflow in hierarchy text, missing visible descendants of offscreen parents, extreme bitmap row dimensions, and semantic labels ignoring the depth limit.

## Run locally

Choose an available iOS Simulator UUID with `xcrun simctl list devices available`. From the repository root:

```sh
xcodebuild -scheme XRay \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO test

xcodebuild -scheme XRay -configuration Release \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO test

xcodebuild -project XRayExample/XRayExample.xcodeproj -scheme XRayExample \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Use `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer` before these commands when the global developer directory points to Command Line Tools or a different Xcode. Add unique `-resultBundlePath` and `-derivedDataPath` arguments when retaining evidence.

## Remaining coverage

- Run on the actual minimum iOS 17 runtime and the current stable iOS 26 / Xcode 26 combination before publishing a release.
- Verify screenshot-button activation and LLDB PNG transfer on a physical device. Simulator validation does not prove connected-device debugging permissions or transfer behavior.
- Hardware-backed, protected, and externally rendered content remains subject to UIKit snapshot limitations; arbitrary layer masks and transformed clipping regions are approximated with rectangles.

See [LLDB.md](LLDB.md) for the debugger workflow and its live validation status. The refactor changes no signing identities, team settings, bundle ownership, or distribution configuration.
