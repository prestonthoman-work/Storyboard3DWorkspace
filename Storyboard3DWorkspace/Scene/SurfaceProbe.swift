//
//  SurfaceProbe.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Finds where things touch an object's actual surface, triangle by triangle, rather than its
/// bounding box, so a character can sit on a round rock or lean on a slanted roof.
enum SurfaceProbe {
    struct Hit {
        var point: SIMD3<Float>
        /// The surface's direction at the hit, facing back toward where the ray came from.
        var normal: SIMD3<Float>
        var distance: Float
    }

    /// The first place a ray meets the object's geometry. Everything is in `space`'s coordinates.
    /// For many rays at one object, make a `Surface` once and cast against it.
    static func cast(from origin: SIMD3<Float>, direction: SIMD3<Float>, at object: Entity, in space: Entity,
                     maxDistance: Float = .infinity) -> Hit? {
        Surface(of: object, in: space).cast(from: origin, direction: direction, maxDistance: maxDistance)
    }

    /// An object's triangles, gathered once into one space, for casting many rays.
    struct Surface {
        private var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        private(set) var bounds: BoundingBox?

        init(of object: Entity, in space: Entity) {
            var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
            var bounds: BoundingBox?
            SurfaceProbe.forEachTriangle(of: object, in: space) { a, b, c in
                triangles.append((a, b, c))
                for point in [a, b, c] {
                    bounds = bounds.map { $0.union(point) } ?? BoundingBox(min: point, max: point)
                }
            }
            self.triangles = triangles
            self.bounds = bounds
        }

        func cast(from origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = .infinity) -> Hit? {
            guard simd_length(direction) > 1e-8, let bounds else { return nil }
            let direction = simd_normalize(direction)
            // Most rays miss the object altogether; skip its triangles then.
            guard let entry = CompositionRenderer.rayEntry(origin: origin, direction: direction, bounds: bounds),
                  entry <= maxDistance else { return nil }
            var nearest: Hit?
            for (a, b, c) in triangles {
                guard let distance = SurfaceProbe.intersect(origin: origin, direction: direction, a, b, c),
                      distance <= maxDistance, distance < (nearest?.distance ?? .infinity) else { continue }
                var normal = simd_cross(b - a, c - a)
                guard simd_length(normal) > 1e-12 else { continue }
                normal = simd_normalize(normal)
                if simd_dot(normal, direction) > 0 { normal = -normal }
                nearest = Hit(point: origin + direction * distance, normal: normal, distance: distance)
            }
            return nearest
        }
    }

    /// Every vertex of the object's geometry, in `space`'s coordinates.
    static func vertices(of object: Entity, in space: Entity, where include: (Entity) -> Bool = { _ in true }) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        forEachMesh(of: object, in: space, where: include) { positions, _, matrix in
            for position in positions {
                let world = matrix * SIMD4(position, 1)
                points.append(SIMD3(world.x, world.y, world.z))
            }
        }
        return points
    }

    // MARK: Geometry

    fileprivate static func forEachTriangle(of object: Entity, in space: Entity,
                                        _ body: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void) {
        forEachMesh(of: object, in: space, where: { _ in true }) { positions, indices, matrix in
            func point(_ index: Int) -> SIMD3<Float> {
                let world = matrix * SIMD4(positions[index], 1)
                return SIMD3(world.x, world.y, world.z)
            }
            if let indices {
                var i = 0
                while i + 2 < indices.count {
                    let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
                    if a < positions.count, b < positions.count, c < positions.count {
                        body(point(a), point(b), point(c))
                    }
                    i += 3
                }
            } else {
                var i = 0
                while i + 2 < positions.count {
                    body(point(i), point(i + 1), point(i + 2))
                    i += 3
                }
            }
        }
    }

    /// Each mesh part's positions and triangle indices under `object`, with the matrix that
    /// takes them into `space`. Editing aids (the selection ring) are skipped.
    private static func forEachMesh(of object: Entity, in space: Entity, where include: (Entity) -> Bool,
                                    _ body: ([SIMD3<Float>], [UInt32]?, simd_float4x4) -> Void) {
        func visit(_ entity: Entity) {
            guard entity.isEnabled, entity.name != WorkspaceScene.selectionIndicatorName else { return }
            if include(entity), let model = entity.components[ModelComponent.self] {
                let entityMatrix = entity.transformMatrix(relativeTo: space)
                let contents = model.mesh.contents
                for instance in contents.instances {
                    guard let meshModel = contents.models[instance.model] else { continue }
                    let matrix = entityMatrix * instance.transform
                    for part in meshModel.parts {
                        body(part.positions.elements, part.triangleIndices?.elements, matrix)
                    }
                }
            }
            entity.children.forEach(visit)
        }
        visit(object)
    }

    /// Möller–Trumbore ray–triangle intersection: the distance along the ray, or nil.
    fileprivate static func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>,
                                  _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float? {
        let edge1 = b - a, edge2 = c - a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)
        guard abs(determinant) > 1e-12 else { return nil }
        let inverse = 1 / determinant
        let t = origin - a
        let u = simd_dot(t, p) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(t, edge1)
        let v = simd_dot(direction, q) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        let distance = simd_dot(edge2, q) * inverse
        return distance > 1e-6 ? distance : nil
    }
}
