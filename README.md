# XRay
XRay is view debugging tool for iOS. Currently, XRay can show all of the view hierarchies in UIKit. For SwiftUI, I'm working on it.

XRay helps you debugging view without using XCode's `Debug View Hierarchy`
<img width="878" alt="debug view" src="https://user-images.githubusercontent.com/12643700/170850603-653ee787-a388-4d46-8ae5-adce39ab22ce.png">


## Demo
https://user-images.githubusercontent.com/12643700/170850041-0c024526-5d14-49c7-9ab5-7e09fe5e2397.mp4


## How to Use
Use XRay in Debug mode only. I don't recommend using it with Swizzling function.

1. Add XRay in your project
<img width="854" alt="Screen Shot 2022-05-29 at 1 17 41 PM" src="https://user-images.githubusercontent.com/12643700/170851983-b966fdb1-cc7c-46fc-9eb8-fcea489f795d.png">

2. Set ScreenShot Notification
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
    #if DEBUG
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenshotTaken),
            name: UIApplication.userDidTakeScreenshotNotification, object: nil
        )
    #endif
        return true
    }

```

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


## ClassNameOption
```swift
func captureXray(classNameOption: ClassNameOption)
```
**Labels**
- Red Label(Center): `ViewController`
- Blue Label(trailing bottom): `Custom View`
- Black Label(leading top): `View`


### ClassNameOption.all
This option shows all of the view hierarchies. 

<img width="487" src="https://user-images.githubusercontent.com/12643700/170850418-e3e73dea-8ad3-4f4e-8153-dad98a1e937b.png">


### ClassNameOption.customClass
This option shows custom view only

<img width="487" src="https://user-images.githubusercontent.com/12643700/170850346-b9466c75-e66e-4742-b1e3-93a16b2351b4.png">

