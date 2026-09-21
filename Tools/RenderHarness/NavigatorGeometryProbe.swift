import Foundation
import SceneKit
import simd

// Run through run_navigator_geometry_probe.py. It compiles the production mesh
// builders, extracted unchanged into a temporary macOS SceneKit subject.
@main
private enum NavigatorGeometryProbe {
    private static var checks = 0

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    private static func vectors(_ geometry: SCNGeometry, _ semantic: SCNGeometrySource.Semantic) -> [[Double]] {
        guard let source = geometry.sources(for: semantic).first else {
            preconditionFailure("Missing geometry source: \(semantic)")
        }
        require(source.usesFloatComponents, "Expected floating point geometry source")
        return (0..<source.vectorCount).map { index in
            (0..<source.componentsPerVector).map { component in
                let offset = source.dataOffset + index * source.dataStride + component * source.bytesPerComponent
                return source.data.withUnsafeBytes { bytes in
                    switch source.bytesPerComponent {
                    case 4: return Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                    case 8: return bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
                    default: preconditionFailure("Unsupported component width")
                    }
                }
            }
        }
    }

    private static func triples(_ values: [[Double]]) -> [SIMD3<Double>] {
        values.map { SIMD3($0[0], $0[1], $0[2]) }
    }

    private static func triangles(_ geometry: SCNGeometry) -> [[Int]] {
        geometry.elements.flatMap { element -> [[Int]] in
            require(element.primitiveType == .triangles, "Expected indexed triangles")
            let indices: [Int] = (0..<(element.primitiveCount * 3)).map { index in
                element.data.withUnsafeBytes { bytes in
                    let offset = index * element.bytesPerIndex
                    switch element.bytesPerIndex {
                    case 2: return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    case 4: return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                    default: preconditionFailure("Unsupported index width")
                    }
                }
            }
            return stride(from: 0, to: indices.count, by: 3).map { Array(indices[$0..<$0 + 3]) }
        }
    }

    private static func inspect(_ geometry: SCNGeometry, label: String, checksRadialDirection: Bool) {
        let points = triples(vectors(geometry, .vertex))
        let normals = triples(vectors(geometry, .normal))
        let faces = triangles(geometry)
        require(points.count == normals.count, "\(label): mismatched vertex/normal counts")
        require(!points.isEmpty && !faces.isEmpty, "\(label): empty mesh")
        var referenced = Set<Int>()
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        for (point, normal) in zip(points, normals) {
            require((0..<3).allSatisfy { point[$0].isFinite && normal[$0].isFinite }, "\(label): nonfinite source")
            require(abs(simd_length(normal) - 1) < 0.001, "\(label): nonunit normal")
            // The hood's tip bends behind the Y axis. Check lower side normals,
            // where radial direction is unambiguous, separately from tip topology.
            if checksRadialDirection, point.y < minY + (maxY - minY) * 0.60 {
                require(normal.x * point.x + normal.z * point.z > 0, "\(label): inward side normal")
            }
        }
        for face in faces {
            require(face.allSatisfy { points.indices.contains($0) }, "\(label): invalid index")
            referenced.formUnion(face)
            let a = points[face[0]], b = points[face[1]], c = points[face[2]]
            let cross = simd_cross(b - a, c - a)
            require(simd_length(cross) > 1e-10, "\(label): degenerate triangle")
            let center = (a + b + c) / 3
            if checksRadialDirection, center.y < minY + (maxY - minY) * 0.60 {
                require(cross.x * center.x + cross.z * center.z > 0, "\(label): inward winding")
            }
        }
        require(referenced.count == points.count, "\(label): unused vertices")
        print("PASS \(label): \(points.count) vertices, \(faces.count) triangles; finite/unit normals, outward winding, no degenerate triangles")
    }

    static func main() {
        let material = SCNMaterial()
        let profile: [(r: Float, y: Float)] = [(0.24, 0), (0.20, 0.4), (0.16, 0.8)]
        let segments = 22
        let closed = NavigatorGeometryProbeSubject.lathe(profile, segments: segments, material: material)
        inspect(closed, label: "closed lathe", checksRadialDirection: true)
        let points = triples(vectors(closed, .vertex))
        let normals = triples(vectors(closed, .normal))
        let uv = vectors(closed, .texcoord)
        require(points.count == profile.count * (segments + 1), "lathe: expected UV seam vertex per ring")
        require(uv.count == points.count, "lathe: UV count mismatch")
        for ring in profile.indices {
            let first = ring * (segments + 1)
            let last = first + segments
            require(simd_distance(points[first], points[last]) < 1e-6, "lathe: open position seam")
            require(simd_distance(normals[first], normals[last]) < 1e-5, "lathe: visible normal seam")
            require(abs(uv[first][0]) < 1e-6 && abs(uv[last][0] - 1) < 1e-6, "lathe: UV seam does not span 0...1")
        }
        print("PASS closed lathe: welded shading across split UV seam")

        let collar = NavigatorGeometryProbeSubject.openLathe(profile, segments: 22, gap: 1.05, material: material)
        inspect(collar, label: "open collar", checksRadialDirection: true)

        let hood = NavigatorGeometryProbeSubject.makeHoodGeometry(NavigatorPalette())
        inspect(hood, label: "hood", checksRadialDirection: true)
        let hoodPoints = triples(vectors(hood, .vertex))
        let top = hoodPoints.map(\.y).max()!
        require(hoodPoints.filter { abs($0.y - top) < 1e-6 }.count == 1, "hood: duplicated apex vertices")
        print("PASS hood: one shared apex")
        print("PASS NavigatorGeometryProbe: \(checks) checks. Shader execution and visual appearance require iOS Simulator verification.")
    }
}
