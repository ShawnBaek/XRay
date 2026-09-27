# Preview validation

Validation date: 27 September 2026. The preview API and design tool are unreleased.
Checks used Xcode 27.0 (27A266a), Swift 6.4 and an iPhone 18 Pro Simulator on iOS 27.
One build, test or Preview render ran at a time.

## Automated checks

| Check | Result and scope |
| --- | --- |
| Package Debug | 22 tests passed after the containment fix; all 6 preview tests passed again after the final canvas and RTL changes. |
| Package Release | 2 tests passed, including public preview API availability without controls, inspection or reference loading. |
| Example interaction | The focused UI test passed in LTR and RTL: typing and counter state survive inspection changes and control-panel collapse; a physical left drag reduces both reference fraction and divider screen position. Both screenshots were inspected. |
| Design tool | 16 Swift tests passed, covering identity, dimensions, checksum, paths, case collisions, SSE framing, and preservation of an existing reference when publication fails. |
| DocC | `xcodebuild docbuild -scheme XRay` succeeded without DocC warnings. |

The final package checks verify SwiftUI environment and UIKit layout direction,
separate inspection sessions, retained state and controller lifetime. The UI test
checks rendered divider position because a fraction-only assertion previously
missed SwiftUI's RTL mirroring.

## Consumer integration

A UIKit note-input consumer uses deterministic fixtures and a bundled Figma
Desktop MCP capture. Its production note-input code is unchanged. Apple's
`BuildProject` completed successfully with no errors. Apple's
`RenderPreview` produced both filled and empty fixtures, and the returned images
were opened and inspected. Review found unwanted margins and overlapping layout;
the fix uses the full canvas, floating collapsible controls and a single UIKit
safe-area owner. Final filled, empty and largest accessibility text-size renders
were inspected without the unwanted white bands. The control panel wraps at
large text sizes, while the collapse and drag glyphs stay inside their handles.
The reference and implementation retain the same logical size.

The design CLI successfully registered and imported the saved real capture into
the consumer's resources and generated its Swift catalog. A later live `doctor`
attempt correctly reported an unavailable active design tab: Figma Desktop had
logged out. A complete fresh capture through the finished CLI therefore remains
unverified. Preview rendering continues from the saved reference without a login.

## Remaining limits

- Recheck live CLI sync after restoring the intended Figma Desktop account and
  exact design file. Desktop MCP does not supply a pinned file version.
- The consumer's synthetic state differs from the source frame; its comparison
  demonstrates alignment and interaction, not approved design pixel parity.
- Development Asset exclusion is configured, but an archive was not produced to
  verify that preview images are absent from the shipped bundle.
- No minimum-runtime, iPad or physical-device preview run was added in this pass.
  Existing validation in [Validation.md](Validation.md) remains historical.
- Live typing and dragging were exercised in the example app. Native automation
  did not produce observable control changes in the consumer's Canvas session;
  its own keyboard and scrolling remain unverified by that route.

Run the focused package tests with
`-only-testing:XRayTests/XRayPreviewTests`, the example UI check with
`-only-testing:XRayExampleUITests/XRayExampleUITests/testPreviewControlsPreserveEditsAndDragInBothDirections`,
and the Mac tool checks with `swift test --package-path Tools/XRayDesign --jobs 1`.
Use a verified available destination and separate result bundles.
