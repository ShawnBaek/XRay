![Swift](https://img.shields.io/badge/Swift-5.6+-orange) ![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20tvOS%20|%20watchOS%20|%20macOS-blue) ![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen) ![License](https://img.shields.io/badge/License-MIT-lightgrey)

# XRay

Visual debugging tool for Apple platforms — inspect view hierarchies at runtime with color-coded overlays.

XRay shows all view hierarchies in UIKit without using Xcode's Debug View Hierarchy. Take a screenshot to trigger the overlay.

<img width="878" alt="XRay debug view overlay" src="https://user-images.githubusercontent.com/12643700/170850603-653ee787-a388-4d46-8ae5-adce39ab22ce.png">

> **Status**: Stable — feature complete. No active development needed.

## Demo

https://user-images.githubusercontent.com/12643700/170850041-0c024526-5d14-49c7-9ab5-7e09fe5e2397.mp4

## Features

- Recursively traverses entire view hierarchy
- Color-coded labels by view type:
  - **Red** (center): ViewController
  - **Blue** (trailing bottom): Custom View
  - **Black** (leading top): Standard View
- Complementary color borders for maximum contrast
- Two filter modes: `.all` (full hierarchy) and `.customClass` (custom views only)
- Debug-only — safely wrapped in `#if DEBUG`

## Requirements

- Swift 5.6+
- iOS 11+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ShawnBaek/XRay.git", from: "1.0.2")
]
```

Or in Xcode: **File > Add Package Dependencies** and enter:

```
https://github.com/ShawnBaek/XRay.git
```

## Usage

### 1. Add Screenshot Notification Listener

In your `AppDelegate.swift`:

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    NotificationCenter.default.addObserver(
        self, selector: #selector(screenshotTaken),
        name: UIApplication.userDidTakeScreenshotNotification, object: nil
    )
    #endif
    return true
}
```

### 2. Handle the Screenshot Event

```swift
#if DEBUG
@objc func screenshotTaken() {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let keyWindow = scene.keyWindow,
          let topViewController = keyWindow.topViewController() else {
        return
    }
    let xray = XRay(rootViewController: topViewController)
    xray.captureXray(classNameOption: .all)
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
        xray.removeXray()
    }
}
#endif
```

### ClassNameOption

#### `.all` — Shows all view hierarchies

<img width="487" src="https://user-images.githubusercontent.com/12643700/170850418-e3e73dea-8ad3-4f4e-8153-dad98a1e937b.png">

#### `.customClass` — Shows custom views only

<img width="487" src="https://user-images.githubusercontent.com/12643700/170850346-b9466c75-e66e-4742-b1e3-93a16b2351b4.png">

## License

MIT License. See [LICENSE](LICENSE) for details.

## Author

Shawn Baek — [GitHub](https://github.com/ShawnBaek) · shawn@shawnbaek.com
