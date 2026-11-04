//
//  WorkspaceTips.swift
//  Storyboard3DWorkspace
//

import SwiftUI
import TipKit

/// One short tip per tab, shown the first time it's opened. TipKit remembers when a
/// tip has been dismissed, so each appears until the person closes it.
struct BaseTip: Tip {
    var title: Text { Text("Your stage") }
    var message: Text? {
        Text("The base sits on your table. Pick a template and size here, or use Find Table to move it to another table.")
    }
    var image: Image? { Image(systemName: "square.3.layers.3d.down.right") }
}

struct ObjectsTip: Tip {
    var title: Text { Text("Build your scene") }
    var message: Text? {
        Text("Generate objects one at a time, then pinch and drag to arrange them. Released objects fall onto the base or stack on each other.")
    }
    var image: Image? { Image(systemName: "cube") }
}

struct BackgroundTip: Tip {
    var title: Text { Text("A backdrop that follows you") }
    var message: Text? {
        Text("The image turns to face you and stays behind your scene as you walk around it.")
    }
    var image: Image? { Image(systemName: "photo") }
}

struct AnimateTip: Tip {
    var title: Text { Text("Keyframes are your shots") }
    var message: Text? {
        Text("Add Keyframe saves the scene as a new shot. Changes save to the selected keyframe automatically, so add a keyframe before starting a new shot.")
    }
    var image: Image? { Image(systemName: "film") }
}

struct CaptureTip: Tip {
    var title: Text { Text("Frame it like a camera") }
    var message: Text? {
        Text("Line up the shot inside the frame in your view. Capture starts a 3-second timer so you can look back at your scene.")
    }
    var image: Image? { Image(systemName: "camera") }
}
