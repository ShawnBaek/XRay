//
//  Xray.swift
//  Travelcrumb
//
//  Created by Sungwook Baek on 2022/05/22.
//  Copyright © 2022 BaekSungwook. All rights reserved.
//

import Foundation
import UIKit

public final class XRay {
    private enum ViewTag {
        static let xray = 20_220_522
    }
    public enum ClassNameOption {
        case all
        case customClass
    }
    private enum Constants {
        enum Label {
            static let left: CGFloat = 0
            static let top: CGFloat = 0
        }
    }
    private weak var rootViewController: UIViewController!
    public init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
    }

    deinit {
        removeXray()
    }

    public func captureXray(classNameOption: ClassNameOption) {
        let subviews = allSubViews(rootView: rootViewController.view)
        let rootViewControllerInfo = classTypeInfo(
            object: rootViewController, option: classNameOption)
        xrayView(
            on: rootViewController.view,
            name: rootViewControllerInfo.name,
            classNameOption: classNameOption)
        subviews.forEach {
            xrayView(on: $0, classNameOption: classNameOption)
        }
    }

    private func allSubViews(rootView: UIView) -> [UIView] {
        rootView.subviews + rootView.subviews.reversed().flatMap { $0.allSubViews() }
    }

    public func refresh(classNameOption: ClassNameOption) {
        captureXray(classNameOption: classNameOption)
    }

    public func removeXray() {
        var allViews = allSubViews(rootView: rootViewController.view)
        allViews.append(rootViewController.view)

        allViews.forEach {
            $0.viewWithTag(ViewTag.xray)?.removeFromSuperview()
        }
    }
}

extension XRay {
    // https://en.wikipedia.org/wiki/Complementary_colors
    // https://gist.github.com/klein-artur/025a0fa4f167a648d9ea
    private func complementaryColor(base color: UIColor?) -> UIColor? {
        guard let color = color else {
            return nil
        }
        let ciColor = CIColor(color: color)
        let compRed: CGFloat = 1.0 - ciColor.red
        let compGreen: CGFloat = 1.0 - ciColor.green
        let compBlue: CGFloat = 1.0 - ciColor.blue
        return UIColor(
            red: compRed,
            green: compGreen,
            blue: compBlue,
            alpha: ciColor.alpha
        )
    }

    private func classTypeInfo(
        object: NSObject,
        option: ClassNameOption
    ) -> (name: String?, isCustomClass: Bool) {
        let objectName = NSStringFromClass(type(of: object))
        let isCustomClass = objectName.contains(".")
        let customClassName = objectName.split(separator: ".").last
        if option == .customClass {
            if isCustomClass,
                let customClassName = customClassName
            {
                return (String(customClassName), isCustomClass)
            }
            return (nil, isCustomClass)
        } else {
            if let customClassName = customClassName {
                return (String(customClassName), isCustomClass)
            }
            return (objectName, isCustomClass)
        }
    }

    private func xrayView(on view: UIView, name: String? = nil, classNameOption: ClassNameOption) {
        guard view.subviews.first(where: { $0.tag == ViewTag.xray }) == nil else {
            return
        }
        let xrayView = UIView()
        let isRootView = name != nil
        let complementaryColor = complementaryColor(base: view.backgroundColor)
        let classInfo = classTypeInfo(object: view, option: classNameOption)
        let isCustomClass = classInfo.isCustomClass

        xrayView.backgroundColor = .clear
        xrayView.layer.borderColor = complementaryColor?.cgColor
        xrayView.layer.borderWidth = 1.0
        xrayView.tag = ViewTag.xray
        xrayView.isUserInteractionEnabled = false
        let descriptionLabel = makeDescriptionLabel(
            isRootView: isRootView,
            name: name,
            classInfo: classInfo
        )
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        xrayView.addSubview(descriptionLabel)
        if isRootView {
            NSLayoutConstraint.activate([
                descriptionLabel.centerXAnchor.constraint(equalTo: xrayView.centerXAnchor),
                descriptionLabel.centerYAnchor.constraint(
                    equalTo: xrayView.centerYAnchor),
            ])
        } else if isCustomClass {
            NSLayoutConstraint.activate([
                descriptionLabel.trailingAnchor.constraint(equalTo: xrayView.trailingAnchor),
                descriptionLabel.bottomAnchor.constraint(
                    equalTo: xrayView.bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                descriptionLabel.leadingAnchor.constraint(
                    equalTo: xrayView.leadingAnchor, constant: Constants.Label.left),
                descriptionLabel.topAnchor.constraint(
                    equalTo: xrayView.topAnchor, constant: Constants.Label.top),
            ])
        }
        xrayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(xrayView)
        NSLayoutConstraint.activate([
            xrayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            xrayView.topAnchor.constraint(equalTo: view.topAnchor),
            xrayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            xrayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeDescriptionLabel(
        isRootView: Bool,
        name: String? = nil,
        classInfo: (name: String?, isCustomClass: Bool)
    ) -> UILabel {
        var labelBackgroundColor: UIColor
        var labelTextColor: UIColor
        var labelFont: UIFont
        if isRootView {
            labelBackgroundColor = .red
            labelTextColor = .white
            labelFont = .systemFont(ofSize: 10, weight: .bold)
        } else if classInfo.isCustomClass {
            labelBackgroundColor = .blue
            labelTextColor = .yellow
            labelFont = .systemFont(ofSize: 10, weight: .semibold)
        } else {
            labelBackgroundColor = .black
            labelTextColor = .yellow
            labelFont = .systemFont(ofSize: 10)
        }
        let descriptionLabel = UILabel()
        descriptionLabel.backgroundColor = labelBackgroundColor
        descriptionLabel.text = name ?? classInfo.name
        descriptionLabel.font = labelFont
        descriptionLabel.textColor = labelTextColor
        return descriptionLabel
    }
}

//https://stackoverflow.com/questions/2746478/how-can-i-loop-through-all-subviews-of-a-uiview-and-their-subviews-and-their-su
fileprivate extension UIView {
    func allSubViews() -> [UIView] {
        subviews + subviews.flatMap { $0.allSubViews() }
    }
}
