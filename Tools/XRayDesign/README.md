# XRay Design tool

A separate macOS Swift package for importing a Figma Desktop MCP snapshot into an offline XRay preview. It has no third-party dependencies and does not belong in the iOS library target.

The tool is not a product of the `XRay` package, so a package dependency on XRay does not provide it. Clone the tag that matches your XRay dependency and run the tool from that clone, so the metadata and catalog it writes match the library that loads them:

```sh
git clone --branch 2.0.0 --depth 1 https://github.com/ShawnBaek/XRay.git /path/to/XRay
swift run --package-path /path/to/XRay/Tools/XRayDesign xray design doctor
swift run --package-path /path/to/XRay/Tools/XRayDesign xray design add example \
  --figma 'https://www.figma.com/design/FILE/Example?node-id=1-2' \
  --resources 'PreviewContent/XRayReferences' \
  --catalog 'PreviewContent/DesignReferences.generated.swift'
swift run --package-path /path/to/XRay/Tools/XRayDesign xray design sync example \
  --confirm-open-file FILE
```

Run from the consumer project's directory, or pass `--manifest path/to/xray-design.json`. Before syncing, verify the personal account and exact file or branch in Figma Desktop, open the linked node, and enable Desktop MCP in Dev Mode. The tool connects only to `http://127.0.0.1:3845/mcp`. It has no PAT, OAuth, remote MCP, or arbitrary-download fallback.

`--confirm-open-file` records an explicit human check for the current command. The local MCP tool does not expose the account or active file key, so the tool cannot independently verify them. Keep the design and active file unchanged during capture. A metadata recheck detects some changes but does not provide an atomic snapshot or detect every style-only edit.

The result contains `reference.png` and `metadata.json` under each named resource directory. Metadata records the source, dimensions, SHA-256, capture time, and MCP server version. Figma file version is absent: a Desktop MCP snapshot is not a version-pinned export. Existing references require `--replace`; failed validation preserves the old reference. Registration updates likewise require `--replace` for an existing name.

The generated catalog takes the owning bundle explicitly:

```swift
#Preview {
    ExampleView().preview(reference: DesignReferences.example(bundle: referenceBundle))
}
```

Set `referenceBundle` to the verified resource owner. A UIKit consumer can use `Bundle(for: PreviewController.self)` when that controller belongs to the resource-owning target. For SwiftPM, add `.copy("XRayReferences")` to that consumer target and pass its `Bundle.module`. Use `.main` only after verifying it resolves the actual resources in the running preview host. Preserve the resource directory hierarchy. For Xcode, add the generated Swift file and folder resource to the intended target. Development Assets can exclude the folder during archive/install; verify the built product. SwiftPM resources are not automatically excluded by `#if DEBUG`.

Previously captured resources can be imported without opening Figma:

```sh
xray design import example --png /path/reference.png --metadata /path/metadata.json
```

This requires the tool's metadata schema, matching source identity, desktop provenance, and matching checksum. It does not synthesize provenance for arbitrary images.

Focused tests (run only with the host build slot available):

```sh
swift test --package-path /path/to/XRay/Tools/XRayDesign --disable-automatic-resolution --jobs 1
```

Tests cover source parsing, explicit file confirmation, metadata rejection, unsafe paths, checksum and geometry validation, replacement denial, previous-reference preservation, and MCP error decoding. Desktop lifecycle and live screenshot export additionally require a real app session; CI should use the checked-in references.
