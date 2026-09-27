# Preview UIKit and SwiftUI

Inspect a screen and compare it with a local design without an app-wide installation.

## Use the same API for each framework

Import XRay in a Debug preview and call `preview(xray:reference:configuration:)`
on a SwiftUI view, a `UIView`, or a `UIViewController`.

```swift
import SwiftUI
import XRay

#Preview("Profile") {
    ProfileView(model: .sample)
        .preview(xray: true)
}

#Preview("UIKit controller") {
    ProfileViewController(model: .sample)
        .preview(xray: true, configuration: .init(showsLabels: false))
}

#Preview("UIKit view") {
    ProfileHeaderView(name: "Taylor")
        .preview(xray: false)
}
```

`#Preview` registers the Canvas entry. `.preview(...)` adds the controls. `xray`
sets the initial switch value; each preview owns subsequent changes and its own
inspection session. Two previews in one window do not share that session with
each other or with a window-level `.xray()` installation.

Give each UIKit preview a fresh view/controller instance. SwiftUI manages its
representable containment. Toggling the controls updates the existing host;
it does not recreate the UIKit controller. SwiftUI environment values propagate
into the inspected content. Add `.xrayView()` to nested custom SwiftUI views
whose semantic type names you want to inspect.

Controller captions use the concrete owning type, such as
`TravelCrumbViewController`. `TravelCrumb().preview(xray: true)` records
`TravelCrumb` automatically. Within a custom SwiftUI `body`, use
`.xrayView(Self.self)` to record that enclosing type instead of the returned
layout container. SwiftUI does not publicly expose every nested original view
type, so nested custom views still need registration.

Captions fit the visible space using modest font reduction and wrapping.
Controller and SwiftUI names take priority over backing UIKit views. Colliding
captions are omitted while their outlines and full hierarchy data remain;
inspection hosting containers do not receive captions.

## Inject fixtures through the screen's normal initializer

Use small, synthetic values at an existing injection seam. For example, preview
an empty note and a multiline note separately. Keep clocks, images and ordering
fixed when they affect the presentation. A preview does not need a special mock
protocol or another persistence layer.

XRay does not disable your screen's services. Supply inert implementations for
network, storage, analytics and account dependencies before creating the screen.
Do not use production data or credentials in fixtures.

## Compare a saved design

```swift
#Preview("Design comparison") {
    ProfileView(model: .sample)
        .preview(
            xray: true,
            reference: .resource("profile", bundle: profileReferenceBundle)
        )
}
```

The explicit bundle must own `XRayReferences/profile/metadata.json` and
`XRayReferences/profile/reference.png`. Use a folder resource in an app or
`.copy("XRayReferences")` in the consumer's Swift package. A package should pass
its own `Bundle.module`; do not assume the Canvas process's `Bundle.main` owns
your resources.

For an image already loaded by your app, use
`XRayPreviewReference.image(image, logicalSize: CGSize(width: 375, height: 812))`.
Logical size is the design size in points, independently of the PNG pixel density.
Both the implementation and design use that same logical canvas and fit together
inside the full preview canvas. The controls float within the safe area and can
be collapsed without resizing or recreating the content. A neutral dark backdrop
marks unused space when the canvas and destination have different aspect ratios.
The helper does not infer device
safe areas, crop an unrelated frame or promise pixel parity between different
screen states.

The design appears to the physical left of the divider. Drag the divider to
compare; accessibility increment/decrement actions move it by ten percent.
Turn Compare off to inspect or interact with the full implementation. The design
image does not intercept touches. The divider's narrow interaction strip does.

Missing or invalid resources display an inline explanation while the screen and
XRay switch remain available. Rendering never downloads a design or reads a token.
After an explicit sync, refresh the Canvas so Xcode rebuilds copied resources.

## Development and Release builds

XRay's controls and inspection host are Debug-only. In Release, `.preview(...)`
returns the underlying content or UIKit adapter without loading a reference.
Put your fixture definitions and imports inside `#if DEBUG` as appropriate.

Conditional Swift compilation does not exclude image files from a bundle. Mark
the app's preview resource directory as a Development Asset to exclude it from
archive/install builds, and verify the resulting product. SwiftPM copied
resources need a separate consumer packaging decision if they must not ship.

## Verify at the appropriate level

A Canvas image proves one fixture renders. Exercise input, switches and the
divider in Live mode to verify Preview interactions. App navigation, storage,
network and device behavior require their own focused validation.
