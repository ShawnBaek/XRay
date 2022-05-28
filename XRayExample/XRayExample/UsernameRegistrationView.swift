//
//  UsernameRegistrationView.swift
//  XRay
//
//  Created by Sungwook Baek on 2022/05/28.
//

import SwiftUI

import Combine
import SwiftUI

struct UsernameRegistrationView: View {
    let saveButtonFont = Font.system(size: 14).weight(.semibold)
    let nameLabelFont = Font.system(size: 12).weight(.medium)
    let usernameTextInputFont = Font.system(size: 20, weight: .semibold)
    @Environment(\.presentationMode) var presentation
    @FocusState var focusField: Bool
    @State var inputText: String = ""
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { [self] in
                    presentation.wrappedValue.dismiss()
                }) {
                    Text("Save").foregroundColor(
                        .black
                    ).font(saveButtonFont).padding(12)
                }
            }.padding([.top], 14)
                .padding([.bottom], 12)
            Text("Enter Username").foregroundColor(.black.opacity(0.4)).font(
                nameLabelFont
            ).frame(maxWidth: .infinity, alignment: .leading).padding([.leading, .trailing], 24)
            VStack(spacing: 4) {
                TextField("Username", text: $inputText).keyboardType(
                    .asciiCapable
                )
                .font(usernameTextInputFont)
                .focused($focusField)
                .lineLimit(1).autocapitalization(.none)
            }.padding([.leading, .trailing], 24)
            Spacer()
        }.background(Color(UIColor.white))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    focusField = true
                }
            }
    }
}

struct UsernameRegistrationViewSwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        UsernameRegistrationView()
    }
}
