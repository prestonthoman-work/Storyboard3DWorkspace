//
//  LowPoly.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Small helpers for building flat-shaded, low-detail geometry.
enum LowPoly {
    static func material(_ color: UIColor, roughness: Float = 0.85) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .float(roughness), isMetallic: false)
    }

    static func box(_ size: SIMD3<Float>, _ color: UIColor, at position: SIMD3<Float>,
                    cornerRadius: Float = 0) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size, cornerRadius: cornerRadius),
                                 materials: [material(color)])
        entity.position = position
        return entity
    }

    static func cylinder(height: Float, radius: Float, _ color: UIColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material(color)])
        entity.position = position
        return entity
    }

    static func cone(height: Float, radius: Float, _ color: UIColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateCone(height: height, radius: radius), materials: [material(color)])
        entity.position = position
        return entity
    }

    static func sphere(radius: Float, _ color: UIColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material(color)])
        entity.position = position
        return entity
    }

    /// A triangular-prism roof with its ridge running along X, resting on y = 0.
    static func gableRoof(width: Float, depth: Float, height: Float) -> MeshResource? {
        let hw = width / 2
        let hd = depth / 2
        let faces: [(vertices: [SIMD3<Float>], normal: SIMD3<Float>)] = [
            ([[hw, 0, -hd], [hw, 0, hd], [hw, height, 0]], [1, 0, 0]),
            ([[-hw, 0, hd], [-hw, 0, -hd], [-hw, height, 0]], [-1, 0, 0]),
            ([[-hw, 0, hd], [hw, 0, hd], [hw, height, 0], [-hw, height, 0]], simd_normalize([0, hd, height])),
            ([[hw, 0, -hd], [-hw, 0, -hd], [-hw, height, 0], [hw, height, 0]], simd_normalize([0, hd, -height])),
            ([[-hw, 0, -hd], [hw, 0, -hd], [hw, 0, hd], [-hw, 0, hd]], [0, -1, 0])
        ]

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for face in faces {
            let start = UInt32(positions.count)
            positions += face.vertices
            normals += Array(repeating: face.normal, count: face.vertices.count)
            // Fan-triangulate, winding each triangle counter-clockwise around its outward normal.
            for i in 1..<(face.vertices.count - 1) {
                let a = face.vertices[0], b = face.vertices[i], c = face.vertices[i + 1]
                if simd_dot(simd_cross(b - a, c - a), face.normal) >= 0 {
                    indices += [start, start + UInt32(i), start + UInt32(i + 1)]
                } else {
                    indices += [start, start + UInt32(i + 1), start + UInt32(i)]
                }
            }
        }

        var descriptor = MeshDescriptor(name: "GableRoof")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
