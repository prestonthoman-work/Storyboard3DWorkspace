//
//  MeshBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Accumulates many small low-poly shapes into one mesh, so scattered detail (grass
/// tufts, pebbles, ripples) costs one entity per color instead of one per shape.
///
/// Shapes are flat-shaded unless noted; every triangle is wound to face outward.
struct MeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    /// Adds a flat triangle, flipped if needed so its face points along `outward`.
    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, outward: SIMD3<Float>) {
        var normal = simd_cross(b - a, c - a)
        guard simd_length(normal) > 1e-12 else { return }
        normal = simd_normalize(normal)
        let start = UInt32(positions.count)
        if simd_dot(normal, outward) >= 0 {
            positions += [a, b, c]
        } else {
            positions += [a, c, b]
            normal = -normal
        }
        normals += [normal, normal, normal]
        indices += [start, start + 1, start + 2]
    }

    /// A cone standing on `base`, optionally tipped toward `lean` (a horizontal offset of the tip).
    mutating func addCone(base: SIMD3<Float>, radius: Float, height: Float, sides: Int = 5,
                          lean: SIMD2<Float> = .zero, twist: Float = 0) {
        let tip = base + SIMD3(lean.x, height, lean.y)
        let center = base + SIMD3(lean.x / 2, height / 3, lean.y / 2)
        let ring = (0..<sides).map { i -> SIMD3<Float> in
            let angle = twist + Float(i) / Float(sides) * 2 * .pi
            return base + SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
        }
        for i in 0..<sides {
            let a = ring[i], b = ring[(i + 1) % sides]
            addTriangle(a, b, tip, outward: (a + b) / 2 - center)
        }
    }

    /// A faceted ellipsoid, like a pebble or a puff of foliage.
    mutating func addBlob(center: SIMD3<Float>, radii: SIMD3<Float>, rings: Int = 4, segments: Int = 6, twist: Float = 0) {
        func point(_ ring: Int, _ segment: Int) -> SIMD3<Float> {
            let phi = Float(ring) / Float(rings) * .pi
            let theta = twist + Float(segment) / Float(segments) * 2 * .pi
            return center + SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radii
        }
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = point(ring, segment), b = point(ring, segment + 1)
                let c = point(ring + 1, segment + 1), d = point(ring + 1, segment)
                let outward = (a + b + c + d) / 4 - center
                if ring > 0 { addTriangle(a, b, c, outward: outward) }
                if ring < rings - 1 { addTriangle(a, c, d, outward: outward) }
            }
        }
    }

    /// An axis-aligned box turned by `yaw` about its vertical axis.
    mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let h = size / 2
        func corner(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            center + rotation.act(SIMD3(x * h.x, y * h.y, z * h.z))
        }
        let faces: [[SIMD3<Float>]] = [
            [corner(1, -1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(1, -1, 1)],
            [corner(-1, -1, -1), corner(-1, -1, 1), corner(-1, 1, 1), corner(-1, 1, -1)],
            [corner(-1, 1, -1), corner(-1, 1, 1), corner(1, 1, 1), corner(1, 1, -1)],
            [corner(-1, -1, -1), corner(1, -1, -1), corner(1, -1, 1), corner(-1, -1, 1)],
            [corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)],
            [corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1), corner(1, -1, -1)]
        ]
        for face in faces {
            let outward = (face[0] + face[1] + face[2] + face[3]) / 4 - center
            addTriangle(face[0], face[1], face[2], outward: outward)
            addTriangle(face[0], face[2], face[3], outward: outward)
        }
    }

    /// A flat ring (annulus) lying in the XZ plane at height `y`, facing up.
    mutating func addRing(innerRadius: Float, outerRadius: Float, y: Float = 0, segments: Int = 64) {
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p0 = SIMD3(cos(a0) * innerRadius, y, sin(a0) * innerRadius)
            let p1 = SIMD3(cos(a0) * outerRadius, y, sin(a0) * outerRadius)
            let p2 = SIMD3(cos(a1) * outerRadius, y, sin(a1) * outerRadius)
            let p3 = SIMD3(cos(a1) * innerRadius, y, sin(a1) * innerRadius)
            addTriangle(p0, p1, p2, outward: [0, 1, 0])
            addTriangle(p0, p2, p3, outward: [0, 1, 0])
        }
    }

    /// A smooth-sided truncated cone (a round plinth) from `bottomY` to `topY`, with
    /// optional flat caps.
    mutating func addFrustum(bottomRadius: Float, topRadius: Float, bottomY: Float, topY: Float,
                             segments: Int = 96, capTop: Bool = true, capBottom: Bool = false) {
        let slope = (bottomRadius - topRadius) / max(topY - bottomY, 1e-6)
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let d0 = SIMD3(cos(a0), 0, sin(a0)), d1 = SIMD3(cos(a1), 0, sin(a1))
            let b0 = d0 * bottomRadius + [0, bottomY, 0], b1 = d1 * bottomRadius + [0, bottomY, 0]
            let t0 = d0 * topRadius + [0, topY, 0], t1 = d1 * topRadius + [0, topY, 0]
            let n0 = simd_normalize(d0 + [0, slope, 0]), n1 = simd_normalize(d1 + [0, slope, 0])

            // Smooth side: per-vertex radial normals.
            let start = UInt32(positions.count)
            positions += [b0, b1, t1, t0]
            normals += [n0, n1, n1, n0]
            let outward = (d0 + d1) / 2
            if simd_dot(simd_cross(b1 - b0, t1 - b0), outward) >= 0 {
                indices += [start, start + 1, start + 2, start, start + 2, start + 3]
            } else {
                indices += [start, start + 2, start + 1, start, start + 3, start + 2]
            }

            if capTop { addTriangle([0, topY, 0], t0, t1, outward: [0, 1, 0]) }
            if capBottom { addTriangle([0, bottomY, 0], b0, b1, outward: [0, -1, 0]) }
        }
    }

    func makeMesh(named name: String) -> MeshResource? {
        guard !isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    func makeEntity(named name: String, material: any RealityKit.Material) -> ModelEntity? {
        makeMesh(named: name).map { ModelEntity(mesh: $0, materials: [material]) }
    }
}

/// A repeatable random sequence, so a template builds the same scatter every time
/// (across undo, reopening the project, and re-renders).
struct ScatterRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func float(_ range: ClosedRange<Float>) -> Float { Float.random(in: range, using: &self) }

    /// A uniformly distributed point on a disc between two radii.
    mutating func pointOnDisc(minRadius: Float = 0, maxRadius: Float) -> SIMD2<Float> {
        let angle = float(0...(2 * .pi))
        let radius = sqrt(float((minRadius * minRadius)...(maxRadius * maxRadius)))
        return [cos(angle) * radius, sin(angle) * radius]
    }
}
