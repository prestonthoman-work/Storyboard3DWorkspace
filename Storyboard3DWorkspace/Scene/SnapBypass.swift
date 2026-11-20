//
//  SnapBypass.swift
//  Storyboard3DWorkspace
//

import GameController

/// Holding Option on a connected keyboard skips snapping for as long as it's held, like in
/// desktop design tools. Without a keyboard, the Snap button on the object's toolbar and the
/// toggles under the panel do the same.
enum SnapBypass {
    static var isHeld: Bool {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return false }
        return keyboard.button(forKeyCode: .leftAlt)?.isPressed == true
            || keyboard.button(forKeyCode: .rightAlt)?.isPressed == true
    }
}
