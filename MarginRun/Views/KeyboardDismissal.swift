import SwiftUI
import UIKit

extension View {
    /// Gives a form two ways out of the keyboard: a swipe anywhere over the
    /// content, and an explicit Done above the keys.
    ///
    /// Both matter because most of MarginRun's fields are decimal pads, which
    /// have no return key — without this the only way back is finding the one
    /// gap between the fields and the keyboard.
    ///
    /// - Note: tapping inert background does *not* dismiss. Every version of
    ///   that tried here either failed to reach presented sheets, or stole the
    ///   tap from whatever control it landed on: closing the keyboard reflows
    ///   the form, so a button tapped mid-edit moves out from under the finger
    ///   and its action never runs. A half-working dismissal that eats button
    ///   taps is worse than none, so it is deliberately left out.
    func keyboardEscapes() -> some View {
        scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .accessibilityIdentifier("keyboardDoneButton")
                }
            }
    }
}
