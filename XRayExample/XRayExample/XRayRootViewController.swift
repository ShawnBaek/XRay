//
//  ViewController.swift
//  XRayExample
//
//  Created by Sungwook Baek on 2022/05/28.
//

import UIKit
import SwiftUI

class XRayRootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func presentUsernameRegistration(_ sender: Any) {
        let usernameRegistrationController = UIHostingController(rootView: UsernameRegistrationView())
        present(usernameRegistrationController, animated: true)
    }

}

