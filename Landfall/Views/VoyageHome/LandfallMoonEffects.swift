import Foundation
import SceneKit
import UIKit

/// Continuous lunar phase derived from an absolute UTC instant. The epoch is
/// NASA's 2000-01-06 18:15 UTC new moon and the cycle is the mean synodic month.
struct LandfallLunarPhase: Equatable, Sendable {
    static let synodicMonthDays = 29.530588853
    static let referenceNewMoon: TimeInterval = 947_182_500

    let cycle: Double

    var ageDays: Double { cycle * Self.synodicMonthDays }
    var illuminatedFraction: Double { 0.5 * (1 - cos(2 * .pi * cycle)) }
    var isWaxing: Bool { cycle < 0.5 }

    static func current(at date: Date = .now) -> Self {
        #if DEBUG
        if let override = debugOverride() {
            return Self(cycle: override)
        }
        #endif
        let cycleSeconds = synodicMonthDays * 86_400
        let elapsedCycles = (date.timeIntervalSince1970 - referenceNewMoon) / cycleSeconds
        return Self(cycle: elapsedCycles - floor(elapsedCycles))
    }

    #if DEBUG
    private static func debugOverride() -> Double? {
        guard let raw = ProcessInfo.processInfo.environment["LANDFALL_MOON_PHASE"]?
            .lowercased()
        else { return nil }
        let named: [String: Double] = [
            "new": 0,
            "waxing-crescent": 0.125,
            "first-quarter": 0.25,
            "waxing-gibbous": 0.375,
            "full": 0.5,
            "waning-gibbous": 0.625,
            "last-quarter": 0.75,
            "waning-crescent": 0.875,
        ]
        if let value = named[raw] { return value }
        guard let value = Double(raw), value.isFinite else { return nil }
        return value - floor(value)
    }
    #endif
}

/// One shared, light-independent moon for home, timer and voyage scenes.
/// Surface shading creates the phase on the sphere itself, so orbiting cameras
/// never reveal a flat masking disc.
enum LandfallMoonEffects {
    static let rootNodeName = "landfallMoon"
    static let surfaceNodeName = "landfallMoonSurface"

    private static let surfaceShader = """
    #pragma arguments
    float uPhase;
    float3 uMoonLight;
    float3 uEarthshine;
    #pragma body
    float3 n = normalize(_surface.normal);
    float angle = uPhase * 6.28318530718;
    // Northern-hemisphere convention: waxing light is on the right and waning
    // light is on the left. A small vertical component softens the exact halves.
    float3 lightDirection = normalize(float3(sin(angle), 0.055, -cos(angle)));
    float lit = smoothstep(-0.035, 0.045, dot(n, lightDirection));

    float2 uv = _surface.diffuseTexcoord;
    float grain = sin(uv.x * 67.0 + sin(uv.y * 19.0) * 2.1)
        * sin(uv.y * 83.0 - sin(uv.x * 23.0) * 1.7);
    float maria = 0.0;
    maria += (1.0 - smoothstep(0.040, 0.115, distance(uv, float2(0.31, 0.46)))) * 0.13;
    maria += (1.0 - smoothstep(0.035, 0.098, distance(uv, float2(0.43, 0.58)))) * 0.10;
    maria += (1.0 - smoothstep(0.026, 0.072, distance(uv, float2(0.60, 0.39)))) * 0.08;
    maria += (1.0 - smoothstep(0.020, 0.060, distance(uv, float2(0.72, 0.53)))) * 0.07;

    float craterRim = 0.0;
    float craterA = distance(uv, float2(0.36, 0.35));
    float craterB = distance(uv, float2(0.55, 0.64));
    float craterC = distance(uv, float2(0.67, 0.30));
    craterRim += smoothstep(0.020, 0.027, craterA) * (1.0 - smoothstep(0.027, 0.037, craterA));
    craterRim += smoothstep(0.014, 0.020, craterB) * (1.0 - smoothstep(0.020, 0.029, craterB));
    craterRim += smoothstep(0.010, 0.016, craterC) * (1.0 - smoothstep(0.016, 0.024, craterC));

    float texture = clamp(0.94 + grain * 0.025 - maria + craterRim * 0.065, 0.72, 1.03);
    float limb = 0.88 + 0.12 * sqrt(clamp(abs(n.z), 0.0, 1.0));
    float3 brightSide = uMoonLight * texture * limb;
    float3 darkSide = uEarthshine * (0.82 + texture * 0.18);
    _surface.diffuse = float4(mix(darkSide, brightSide, lit), 1.0);
    """

    static func makeNode(
        phase: LandfallLunarPhase = .current(),
        radius: CGFloat = 1.1
    ) -> SCNNode {
        let root = SCNNode()
        root.name = rootNodeName

        for (scale, baseOpacity, order) in [
            (CGFloat(1.11), CGFloat(0.035), -12),
        ] {
            let geometry = SCNSphere(radius: radius * scale)
            geometry.segmentCount = 48
            let material = SCNMaterial()
            material.name = "landfall-moon-halo-material"
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(rgb: 0xE8FFF4)
            material.blendMode = .alpha
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            geometry.firstMaterial = material
            let halo = SCNNode(geometry: geometry)
            halo.name = "landfallMoonHalo"
            halo.renderingOrder = order
            halo.opacity = haloOpacity(for: phase, base: baseOpacity)
            root.addChildNode(halo)
        }

        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 64
        let material = SCNMaterial()
        material.name = "landfall-lunar-phase-material"
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: 0xF1E8CE)
        material.isDoubleSided = false
        material.shaderModifiers = [.surface: surfaceShader]
        material.setValue(NSNumber(value: Float(phase.cycle)), forKey: "uPhase")
        material.setValue(colorVector(0xF5EBCF), forKey: "uMoonLight")
        material.setValue(colorVector(0x071C1A), forKey: "uEarthshine")
        sphere.firstMaterial = material
        let surface = SCNNode(geometry: sphere)
        surface.name = surfaceNodeName
        surface.renderingOrder = 0
        root.addChildNode(surface)
        return root
    }

    static func update(_ root: SCNNode?, phase: LandfallLunarPhase) {
        guard let root else { return }
        root.childNode(withName: surfaceNodeName, recursively: true)?
            .geometry?.firstMaterial?
            .setValue(NSNumber(value: Float(phase.cycle)), forKey: "uPhase")
        let bases: [CGFloat] = [0.035]
        for (index, halo) in root.childNodes
            .filter({ $0.name == "landfallMoonHalo" })
            .enumerated() {
            halo.opacity = haloOpacity(
                for: phase,
                base: bases[min(index, bases.count - 1)]
            )
        }
    }

    private static func haloOpacity(
        for phase: LandfallLunarPhase,
        base: CGFloat
    ) -> CGFloat {
        let illumination = CGFloat(phase.illuminatedFraction)
        return 0.003 + base * sqrt(max(illumination, 0))
    }

    private static func colorVector(_ rgb: UInt) -> SCNVector3 {
        SCNVector3(
            Float((rgb >> 16) & 0xFF) / 255,
            Float((rgb >> 8) & 0xFF) / 255,
            Float(rgb & 0xFF) / 255
        )
    }
}
