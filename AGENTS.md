# Working on XRay

## Scope and ownership

- Work in the requested checkout and preserve existing changes. Confirm the branch,
  remote and affected consumer before editing. Use one writer per checkout and
  one heavy build or Preview render at a time.
- Keep personal account IDs, signing teams, credentials and machine-specific paths
  in private configuration. Do not commit them here.
- Do not commit, push, publish or merge unless the user authorizes that action.

## Package contract

- `Package.swift` defines a Swift 6 library supporting iOS/iPadOS 17 and later.
  Preserve existing public APIs and the inactive Release behavior.
- UI work belongs on the main actor. Inspection must not intercept app touches,
  expose its own overlays as inspected content, or retain inspected views forever.
- Each `.preview(...)` owns an independent inspection session. Preserve SwiftUI
  state/environment and UIKit containment, input and controller identity when
  controls change. Keep fixtures deterministic and free of live services.
- Mount the overlay in a plain UIKit container with a child hosting controller;
  adding arbitrary overlay subviews to `UIHostingController.view` is unsupported.
  Keep comparison layers in one logical coordinate space. Floating controls must
  not resize the canvas, and UIKit previews must not apply safe-area insets twice.
- Preview design references load local resources from an explicit owning bundle.
  Network access and Figma authentication belong to an explicit Mac sync step.
  Never fabricate a Figma reference, file version or successful visual comparison.

## Use Apple's exposed Xcode tools first

1. Inspect the selected Xcode and its current MCP tools. Prefer Apple's official
   Xcode bridge and Apple-authored skills for this installation.
2. A missing Xcode namespace in an agent's initial tool list does not prove the
   tools are unavailable. Check `xcrun mcpbridge --help`; the official bridge
   speaks JSON-RPC over stdio. To target an already open Xcode app, use its verified
   process ID in `MCP_XCODE_PID`; the default route may target the headless service.
   Initialize it, inspect `tools/list`, then make a bounded read-only
   `XcodeListWindows` (windowed) or `XcodeListWorkspaces` (headless) call. Do not enable unsafe permission
   modes or silently replace the user's MCP configuration.
3. Bind calls to the exact open tab identifier or workspace identifier/path,
   according to that connection's live schema. Discover schemes and
   destinations through the exposed tools instead of guessing another project.
4. For Preview work, use the discovered `RenderPreview` schema with the source's
   Xcode project path and the intended zero-based preview definition index.
   The tool builds and renders the preview. Inspect any returned errors before
   claiming success.
5. Open and visually inspect the returned `previewSnapshotPath` yourself. Check
   the reported preview name, source line and actual rendered destination; the
   rendering destination can differ from the selected run destination. Check
   clipping, layout, controls, reference alignment and missing-resource messages.
6. Fix actionable findings and render again. Only pass localization, variant or
   Canvas-control overrides that a previous response reports as supported.
   A static snapshot does not prove typing, dragging, state retention or teardown;
   exercise those separately when affected by the change.

## Focused verification and documentation

- Run the smallest checks that prove the change. Retain the existing XCTest style
  for UIKit/SwiftUI lifecycle tests; use Swift tests for Mac sync logic.
- Verify Debug functionality and Release inactivity when shared preview APIs
  change. Validate reference checksums, dimensions and failure preservation when
  changing resource loading or sync.
- Report actual results and remaining gaps. Build success, a rendered image and
  interactive behavior are different evidence levels.
- Keep public API comments, DocC and README examples aligned. Document bundle
  ownership and development-asset packaging; `#if DEBUG` does not remove copied
  images from a shipped bundle.
- Obtain an independent review of the frozen diff, assess its findings, fix real
  issues and rerun the affected checks. Avoid unrelated refactors or broad tests.

Official reference: [Giving external agents access to Xcode](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode).
