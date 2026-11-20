//
//  BackdropVisibility.swift
//  Storyboard3DWorkspace
//

import Foundation
import Observation

/// Whether the backdrop image shows in the room while you edit.
enum BackdropVisibility: String, CaseIterable, Identifiable {
    /// The image stays up the whole time.
    case alwaysShow
    /// The image stays out of the way while you build, and comes up only for a photo.
    case hideBetweenPhotos

    var id: Self { self }

    var title: String {
        switch self {
        case .alwaysShow: "Always Show"
        case .hideBetweenPhotos: "Hide Between Photos"
        }
    }

    var symbol: String {
        switch self {
        case .alwaysShow: "eye"
        case .hideBetweenPhotos: "eye.slash"
        }
    }
}

/// The person's backdrop preference, and the photo in progress that may show the image for
/// a while without changing that preference.
///
/// With Hide Between Photos, the image comes up when a photo starts (the shutter, or Show to
/// Frame), stays up while framing, counting down, and developing, and goes away once the
/// photo is taken or the person leaves the camera. A failed photo leaves it up for a retry.
@MainActor
@Observable
final class BackdropVisibilityController {
    static let defaultsKey = "backdropVisibility"

    @ObservationIgnored private let defaults: UserDefaults

    /// Saved immediately and read back synchronously at launch, so the first frame is right.
    var preference: BackdropVisibility {
        didSet {
            guard preference != oldValue else { return }
            defaults.set(preference.rawValue, forKey: Self.defaultsKey)
        }
    }

    /// A photo is being lined up or taken. Only matters with Hide Between Photos.
    private(set) var isPhotoInProgress = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = defaults.string(forKey: Self.defaultsKey).flatMap(BackdropVisibility.init) ?? .alwaysShow
    }

    /// Whether the image should be in the room right now.
    var isVisible: Bool { preference == .alwaysShow || isPhotoInProgress }

    /// The image is up only for the photo in progress, and will hide again afterward.
    var isShownForPhoto: Bool { preference == .hideBetweenPhotos && isPhotoInProgress }

    /// The shutter was pressed, or the person asked to see the image to frame a shot.
    func photoStarted() {
        isPhotoInProgress = true
    }

    /// The photo was taken: back to how the person likes to edit.
    func photoTaken() {
        isPhotoInProgress = false
    }

    /// The photo didn't come out. Keep the image up so the shot can be retried as framed.
    func photoFailed() {}

    /// The person left the camera (closed the viewfinder, switched tabs, closed the space, or
    /// chose Hide Now).
    func photoWorkflowEnded() {
        isPhotoInProgress = false
    }
}
