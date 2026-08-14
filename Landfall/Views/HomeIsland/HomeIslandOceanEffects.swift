import SceneKit
import UIKit

struct HomeIslandOceanScene {
    let root: SCNNode
    let animatedMaterial: SCNMaterial
}

/// Bright, layered water authored specifically for the close third-person
/// camera on My Island. Wave shape, normal direction, color, shimmer and shore
/// foam all move independently so the surface never reads as one sliding tile.
enum HomeIslandOceanEffects {
    private static let clockOrigin = ProcessInfo.processInfo.systemUptime

    /// One process-wide wave clock keeps every view of the same ocean in phase.
    /// It also prevents a fallback/standalone timer scene from visibly restarting
    /// its wave field when the SwiftUI presentation hierarchy changes.
    static var currentTime: Float {
        Float(ProcessInfo.processInfo.systemUptime - clockOrigin)
    }

    struct Layout {
        let width: CGFloat
        let depth: CGFloat
        let widthSegments: Int
        let depthSegments: Int
        let centerX: Float
        let surfaceY: Float
        let includesShoreline: Bool
        let includesHorizon: Bool
        let rootName: String

        static let homeIsland = Layout(
            width: 180,
            depth: 180,
            widthSegments: 144,
            depthSegments: 144,
            centerX: 0,
            surfaceY: -0.55,
            includesShoreline: true,
            includesHorizon: true,
            rootName: "home-island-ocean-root"
        )

        /// The voyage home needs a longer plane and a zero waterline, but uses
        /// the exact same colors, wave field, caustics and glints as My Island.
        static let voyageHome = Layout(
            width: 240,
            depth: 170,
            widthSegments: 144,
            depthSegments: 96,
            centerX: 24,
            surfaceY: 0,
            includesShoreline: false,
            includesHorizon: false,
            rootName: "homeSea"
        )

        /// The timer keeps its existing close orbit composition, so it needs a
        /// square surface centered on the boat. Density matches My Island while
        /// staying below the fragment/vertex cost that would compromise 60 fps.
        static let timerVoyage = Layout(
            width: 96,
            depth: 96,
            widthSegments: 144,
            depthSegments: 144,
            centerX: 0,
            surfaceY: 0,
            includesShoreline: false,
            includesHorizon: false,
            rootName: "voyagingSea"
        )
    }

    static let surfaceNodeName = "landfall-shared-ocean-surface"

    private static let geometryShader = """
    #pragma arguments
    float uTime;
    float3 uSurfaceSize;
    float3 uCoordinateOffset;
    #pragma body
    float2 localP = _geometry.position.xy;
    float2 p = localP + uCoordinateOffset.xy;
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float calm = mix(0.42, 1.0, smoothstep(11.0, 34.0, distanceFromIsland));
    float warpPhase = p.x * 0.058 + p.y * 0.081 - uTime * 0.23;
    float warp = sin(warpPhase) * 1.05;
    float2 q = p + float2(warp, -warp * 0.48);
    float phaseA = q.y * 0.145 + q.x * 0.098 - uTime * 0.43;
    float phaseB = q.y * 0.118 - q.x * 0.112 + uTime * 0.34;
    float phaseC = q.y * 0.430 + q.x * 0.345 - uTime * 0.74;
    float phaseD = q.y * 0.940 - q.x * 0.670 + uTime * 1.16;
    float height = (
        sin(phaseA) * 0.145
        + sin(phaseB) * 0.082
        + sin(phaseC) * 0.024
        + sin(phaseD) * 0.007
    ) * calm;
    float dWarpX = cos(warpPhase) * 1.05 * 0.058;
    float dWarpY = cos(warpPhase) * 1.05 * 0.081;
    float dhdx = (
        cos(phaseA) * 0.145 * (0.098 + dWarpX)
        + cos(phaseB) * 0.082 * (-0.112 - dWarpX * 0.48)
        + cos(phaseC) * 0.024 * 0.345
        + cos(phaseD) * 0.007 * -0.670
    ) * calm;
    float dhdy = (
        cos(phaseA) * 0.145 * (0.145 + dWarpY)
        + cos(phaseB) * 0.082 * (0.118 - dWarpY * 0.48)
        + cos(phaseC) * 0.024 * 0.430
        + cos(phaseD) * 0.007 * 0.940
    ) * calm;
    float edgeX = 1.0 - smoothstep(
        uSurfaceSize.x * 0.43,
        uSurfaceSize.x * 0.50,
        abs(localP.x)
    );
    float edgeY = 1.0 - smoothstep(
        uSurfaceSize.y * 0.43,
        uSurfaceSize.y * 0.50,
        abs(localP.y)
    );
    float edge = edgeX * edgeY;
    _geometry.position.z += height * edge;
    _geometry.normal = normalize(float3(-dhdx * edge, -dhdy * edge, 1.0));
    """

    private static let surfaceShader = """
    #pragma arguments
    float uTime;
    float3 uShallow;
    float3 uSea;
    float3 uDeep;
    float3 uLight;
    float3 uFog;
    float3 uSurfaceSize;
    float3 uCoordinateOffset;
    float uShoreline;
    #pragma body
    float2 localP = (_surface.diffuseTexcoord - 0.5) * uSurfaceSize.xy;
    float2 p = localP + uCoordinateOffset.xy;
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float calm = mix(0.42, 1.0, smoothstep(11.0, 34.0, distanceFromIsland));
    float warpPhase = p.x * 0.058 + p.y * 0.081 - uTime * 0.23;
    float warp = sin(warpPhase) * 1.05;
    float2 q = p + float2(warp, -warp * 0.48);
    float phaseA = q.y * 0.145 + q.x * 0.098 - uTime * 0.43;
    float phaseB = q.y * 0.118 - q.x * 0.112 + uTime * 0.34;
    float phaseC = q.y * 0.430 + q.x * 0.345 - uTime * 0.74;
    float phaseD = q.y * 0.940 - q.x * 0.670 + uTime * 1.16;
    float height = (
        sin(phaseA) * 0.145
        + sin(phaseB) * 0.082
        + sin(phaseC) * 0.024
        + sin(phaseD) * 0.007
    ) * calm;
    float dWarpX = cos(warpPhase) * 1.05 * 0.058;
    float dWarpY = cos(warpPhase) * 1.05 * 0.081;
    float2 slope = float2(
        cos(phaseA) * 0.145 * (0.098 + dWarpX)
            + cos(phaseB) * 0.082 * (-0.112 - dWarpX * 0.48)
            + cos(phaseC) * 0.024 * 0.345
            + cos(phaseD) * 0.007 * -0.670,
        cos(phaseA) * 0.145 * (0.145 + dWarpY)
            + cos(phaseB) * 0.082 * (0.118 - dWarpY * 0.48)
            + cos(phaseC) * 0.024 * 0.430
            + cos(phaseD) * 0.007 * 0.940
    ) * calm;

    float shallowMix = smoothstep(9.5, 24.0, distanceFromIsland);
    float deepMix = smoothstep(31.0, 82.0, distanceFromIsland);
    float3 col = mix(uShallow, uSea, shallowMix);
    col = mix(col, uDeep, deepMix * 0.72);
    float directionalShade = clamp(0.52 + slope.x * 3.6 + slope.y * 3.1, 0.0, 1.0);
    col *= 0.975 + directionalShade * 0.07;

    float trough = 1.0 - smoothstep(-0.13, 0.008, height);
    float crest = smoothstep(0.035, 0.155, height);
    col = mix(col, uDeep, trough * 0.055);
    col = mix(col, uLight, crest * 0.16);

    // Two warped wave fields meet in short curved ridges. This avoids the
    // straight, texture-like bands that are especially obvious in perspective.
    float causticA = sin(
        q.x * 0.82 + sin(q.y * 0.21 - uTime * 0.37) * 1.55 + uTime * 0.68
    );
    float causticB = sin(
        q.y * 0.91 + sin(q.x * 0.24 + uTime * 0.29) * 1.45 - uTime * 0.57
    );
    float causticC = sin(
        (q.x - q.y) * 1.07 + sin((q.x + q.y) * 0.17) * 1.2 + uTime * 0.43
    );
    float causticRidge = 1.0 - smoothstep(0.018, 0.16, abs(causticA + causticB));
    float causticCross = 1.0 - smoothstep(0.02, 0.145, abs(causticB + causticC));
    float caustic = max(causticRidge, causticCross * 0.58);
    float nearShore = 1.0 - smoothstep(13.0, 42.0, distanceFromIsland);
    col = mix(col, uLight, caustic * nearShore * 0.14);

    // Recreate the exact authored sand outline in water space. Procedural lace
    // stays on the surface and can never turn into a dark occluding object.
    float shoreAngle = atan2(p.y / 9.10, p.x / 13.10);
    float shorelineRipple = sin(shoreAngle * 3.0 + 0.45) * 0.045
        + sin(shoreAngle * 7.0 - 0.82) * 0.026
        + sin(shoreAngle * 11.0 + 1.3) * 0.012;
    float shorelineShift = sin(shoreAngle * 5.0 + 0.91) * 0.018;
    float shorelineScale = 0.955 * (1.0 + shorelineRipple + shorelineShift);
    float ellipseRadius = length(float2(p.x / 13.10, p.y / 9.10));
    float shoreDistance = (ellipseRadius - shorelineScale) * 10.8;
    float wash = 0.105
        + sin(shoreAngle * 5.0 - uTime * 0.74) * 0.028
        + sin(shoreAngle * 13.0 + uTime * 0.43) * 0.016;
    float foamRidge = 1.0 - smoothstep(0.018, 0.088, abs(shoreDistance - wash));
    float foamBreak = 0.5 + 0.5 * sin(
        shoreAngle * 23.0 + sin(shoreAngle * 9.0) * 1.6 - uTime * 0.92
    );
    float foamLace = 0.5 + 0.5 * sin(
        shoreAngle * 41.0 - sin(shoreAngle * 17.0) * 1.1 + uTime * 0.61
    );
    float fragments = max(
        smoothstep(0.46, 0.72, foamBreak),
        smoothstep(0.70, 0.91, foamLace) * 0.48
    );
    float waterSide = smoothstep(-0.015, 0.045, shoreDistance);
    float shoreFoam = foamRidge * fragments * waterSide * uShoreline;
    col = mix(col, uLight, shoreFoam * 0.58);

    // Crossing masks turn highlights into scattered glints instead of stripes.
    float glintA = 0.5 + 0.5 * sin(
        p.x * 1.47 - p.y * 1.91 + sin(p.y * 0.19) * 1.7 - uTime * 1.46
    );
    float glintB = 0.5 + 0.5 * sin(
        p.y * 2.31 + p.x * 0.73 + sin(p.x * 0.23) * 1.3 + uTime * 1.13
    );
    float sparkle = smoothstep(0.76, 0.985, glintA * glintB)
        * smoothstep(0.025, 0.14, height)
        * (1.0 - smoothstep(18.0, 76.0, distanceFromIsland));
    col = mix(col, uLight, sparkle * 0.36);

    float horizon = smoothstep(58.0, 90.0, distanceFromIsland);
    col = mix(col, uFog, horizon * 0.24);
    _surface.diffuse = float4(clamp(col, 0.0, 1.0), 1.0);
    """

    static func makeScene(layout: Layout = .homeIsland) -> HomeIslandOceanScene {
        let root = SCNNode()
        root.name = layout.rootName

        let plane = SCNPlane(width: layout.width, height: layout.depth)
        plane.widthSegmentCount = layout.widthSegments
        plane.heightSegmentCount = layout.depthSegments
        let material = SCNMaterial()
        material.name = "home-island-ocean-material"
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: 0x3AB9B5)
        material.isDoubleSided = true
        material.shaderModifiers = [
            .geometry: geometryShader,
            .surface: surfaceShader,
        ]
        material.setValue(NSNumber(value: currentTime), forKey: "uTime")
        material.setValue(colorVector(0x22DDBD), forKey: "uShallow")
        material.setValue(colorVector(0x18B9C9), forKey: "uSea")
        material.setValue(colorVector(0x087895), forKey: "uDeep")
        material.setValue(colorVector(0xEFFFF7), forKey: "uLight")
        material.setValue(colorVector(0x93D9D3), forKey: "uFog")
        material.setValue(
            SCNVector3(Float(layout.width), Float(layout.depth), 0),
            forKey: "uSurfaceSize"
        )
        material.setValue(SCNVector3(layout.centerX, 0, 0), forKey: "uCoordinateOffset")
        material.setValue(
            NSNumber(value: layout.includesShoreline ? Float(1) : Float(0)),
            forKey: "uShoreline"
        )
        plane.firstMaterial = material

        let surface = SCNNode(geometry: plane)
        surface.name = surfaceNodeName
        surface.categoryBitMask = 1 << 4
        surface.eulerAngles.x = -.pi / 2
        surface.position = SCNVector3(layout.centerX, layout.surfaceY, 0)
        root.addChildNode(surface)

        let underlayGeometry = SCNPlane(width: layout.width, height: layout.depth)
        let underlayMaterial = SCNMaterial()
        underlayMaterial.lightingModel = .constant
        underlayMaterial.diffuse.contents = UIColor(rgb: 0x28A7B7)
        underlayMaterial.isDoubleSided = true
        underlayGeometry.firstMaterial = underlayMaterial
        let underlay = SCNNode(geometry: underlayGeometry)
        underlay.name = "home-island-ocean-underlay"
        underlay.categoryBitMask = 1 << 4
        underlay.eulerAngles.x = -.pi / 2
        // The four displacement layers can reach about 0.26 m at full swell.
        // Keep the safety layer below that entire range so a trough never
        // reveals it as a moving dark oval.
        underlay.position = SCNVector3(layout.centerX, layout.surfaceY - 0.50, 0)
        root.addChildNode(underlay)

        if layout.includesHorizon {
            let horizonGeometry = SCNTorus(ringRadius: 72, pipeRadius: 0.032)
            horizonGeometry.ringSegmentCount = 192
            horizonGeometry.pipeSegmentCount = 5
            let horizonMaterial = SCNMaterial()
            horizonMaterial.lightingModel = .constant
            horizonMaterial.diffuse.contents = UIColor(rgb: 0xD8FFF4).withAlphaComponent(0.18)
            horizonMaterial.blendMode = .alpha
            horizonMaterial.writesToDepthBuffer = false
            horizonGeometry.firstMaterial = horizonMaterial
            let horizon = SCNNode(geometry: horizonGeometry)
            horizon.name = "home-island-bright-horizon"
            horizon.categoryBitMask = 1 << 4
            horizon.position = SCNVector3(layout.centerX, layout.surfaceY + 0.12, 0)
            root.addChildNode(horizon)
        }

        return HomeIslandOceanScene(root: root, animatedMaterial: material)
    }

    private static func colorVector(_ rgb: UInt) -> SCNVector3 {
        SCNVector3(
            Float((rgb >> 16) & 0xFF) / 255,
            Float((rgb >> 8) & 0xFF) / 255,
            Float(rgb & 0xFF) / 255
        )
    }
}
