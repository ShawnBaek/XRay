# Xray
Xray is viewDebugging tool for iOS. Currently, XRay can show all of the view hierarchies in UIKit. For SwiftUI, I'm working on it.

XRay helps you view debugging without using XCode's `Debug View Hierarchy`
<img width="878" alt="debug view" src="https://user-images.githubusercontent.com/12643700/170850603-653ee787-a388-4d46-8ae5-adce39ab22ce.png">


## Demo
https://user-images.githubusercontent.com/12643700/170850041-0c024526-5d14-49c7-9ab5-7e09fe5e2397.mp4


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

