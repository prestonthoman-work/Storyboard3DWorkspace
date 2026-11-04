//
//  PhotoViews.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A 16:9 photo with rounded corners, or a placeholder message when there's no photo.
struct PhotoFrame<Placeholder: View>: View {
    let image: UIImage?
    @ViewBuilder var placeholder: Placeholder

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A selectable thumbnail, with a star when it's its keyframe's primary photo.
struct PhotoThumbnail: View {
    let photo: CapturedPhoto
    let isSelected: Bool
    let isPrimary: Bool
    var width: CGFloat = 112
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(uiImage: photo.thumbnail)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .padding(5)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(isPrimary ? "Primary photo" : "Photo")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
