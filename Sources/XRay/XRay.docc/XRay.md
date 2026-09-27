# ``XRay``

Inspect UIKit and SwiftUI views, including independent Xcode previews.

## Overview

Use `XRay.install(in:)` for window-level runtime inspection, or call
`.preview(xray:reference:configuration:)` on a SwiftUI view, UIKit view or view
controller inside `#Preview`. Preview controls retain the inspected content
and can compare it with a saved design image without a network connection.

## Topics

### Xcode previews

- <doc:Previewing>
- <doc:DesignReferences>
- ``XRayPreviewReference``
