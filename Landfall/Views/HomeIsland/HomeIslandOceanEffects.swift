import SceneKit
import UIKit

struct HomeIslandOceanScene {
    let root: SCNNode
    let animatedMaterial: SCNMaterial
}

/// Layered coastal water shared by My Island, the voyage home and the timer.
/// Geometry carries the swells while the surface shader supplies fine normals,
/// optical depth, sky light and foam without texture lookups.
enum HomeIslandOceanEffects {
    private static let clockOrigin = ProcessInfo.processInfo.systemUptime

    struct Appearance {
        let shallow: UInt
        let sea: UInt
        let deep: UInt
        let light: UInt
        let sky: UInt
        let horizon: UInt
        let sun: UInt
        let fog: UInt
        let sunDirection: SCNVector3
        let sunStrength: Float

        static let daylight = Appearance(
            shallow: 0x39CAB4,
            sea: 0x127F9C,
            deep: 0x043B62,
            light: 0xF4FFF9,
            sky: 0x4A9DCA,
            horizon: 0xC7F2E9,
            sun: 0xFFF1C7,
            fog: 0x6BA1AA,
            sunDirection: SCNVector3(-0.34, 0.72, 0.60),
            sunStrength: 1
        )
    }

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
        let rootName: String

        static let homeIsland = Layout(
            width: 180,
            depth: 180,
            widthSegments: MetalRenderingProfile.current.oceanSegments(base: 144),
            depthSegments: MetalRenderingProfile.current.oceanSegments(base: 144),
            centerX: 0,
            surfaceY: -0.55,
            includesShoreline: true,
            rootName: "home-island-ocean-root"
        )

        /// The voyage home needs a longer plane and a zero waterline, but uses
        /// the exact same colors, wave field, caustics and glints as My Island.
        static let voyageHome = Layout(
            width: 240,
            depth: 170,
            widthSegments: MetalRenderingProfile.current.oceanSegments(base: 144),
            depthSegments: MetalRenderingProfile.current.oceanSegments(base: 96),
            centerX: 24,
            surfaceY: 0,
            includesShoreline: false,
            rootName: "homeSea"
        )

        /// The timer keeps its existing close orbit composition, so it needs a
        /// square surface centered on the boat. Density matches My Island while
        /// staying below the fragment/vertex cost that would compromise 60 fps.
        static let timerVoyage = Layout(
            width: 96,
            depth: 96,
            widthSegments: MetalRenderingProfile.current.oceanSegments(base: 144),
            depthSegments: MetalRenderingProfile.current.oceanSegments(base: 144),
            centerX: 0,
            surfaceY: 0,
            includesShoreline: false,
            rootName: "voyagingSea"
        )
    }

    static let surfaceNodeName = "landfall-shared-ocean-surface"

    /// Shared source keeps the displaced surface, its normals and CPU-side
    /// sampler on one compact wave spectrum. `p`, `uTime` and
    /// `distanceFromIsland` are supplied by each modifier stage.
    private static let waveSpectrumShader = """
    float calm = mix(0.36, 1.0, smoothstep(10.0, 34.0, distanceFromIsland));
    float2 dirA = float2(0.342, 0.940);
    float2 dirB = float2(-0.766, 0.643);
    float2 dirC = float2(0.906, 0.423);
    float2 dirD = float2(-0.259, 0.966);
    float2 dirE = float2(0.643, -0.766);
    float basePhaseA = dot(p, dirA) * 0.105 - uTime * 0.42;
    float basePhaseB = dot(p, dirB) * 0.155 - uTime * 0.36 + 1.70;
    float phaseC = dot(p, dirC) * 0.340 - uTime * 0.78 + 0.45;
    float phaseD = dot(p, dirD) * 0.720 - uTime * 1.22 + 2.10;
    float phaseE = dot(p, dirE) * 1.250 - uTime * 1.68 + 0.90;
    float sinC = sin(phaseC);
    float sinD = sin(phaseD);
    float sinE = sin(phaseE);
    // Cross seas bend the long swells without adding another wave component.
    // This avoids evenly spaced horizon bands while keeping motion coherent.
    float phaseA = basePhaseA + sinC * 0.34 + sinD * 0.10;
    float phaseB = basePhaseB - sinD * 0.26 + sinE * 0.08;
    float sinA = sin(phaseA);
    float sinB = sin(phaseB);
    float cosA = cos(phaseA);
    float cosB = cos(phaseB);
    float cosC = cos(phaseC);
    float cosD = cos(phaseD);
    float cosE = cos(phaseE);
    float height = (
        sinA * 0.150
        + sinB * 0.090
        + sinC * 0.035
        + sinD * 0.014
        + sinE * 0.005
    ) * calm;
    float2 gradientA = (
        dirA * 0.105
        + dirC * (cosC * 0.340 * 0.34)
        + dirD * (cosD * 0.720 * 0.10)
    );
    float2 gradientB = (
        dirB * 0.155
        - dirD * (cosD * 0.720 * 0.26)
        + dirE * (cosE * 1.250 * 0.08)
    );
    float2 slope = (
        gradientA * (cosA * 0.150)
        + gradientB * (cosB * 0.090)
        + dirC * (cosC * 0.035 * 0.340)
        + dirD * (cosD * 0.014 * 0.720)
        + dirE * (cosE * 0.005 * 1.250)
    ) * calm;
    """

    private static let geometryShader = """
    #pragma arguments
    float uTime;
    float3 uSurfaceSize;
    float3 uCoordinateOffset;
    #pragma body
    float2 localP = _geometry.position.xy;
    float2 p = localP + uCoordinateOffset.xy;
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    \(waveSpectrumShader)
    // Five directional components make a compact Gerstner-style field. The
    // first three also move vertices laterally, giving crests a real profile
    // instead of simply lifting a flat grid.
    float2 horizontal = (
        dirA * (cosA * 0.150 * 0.62)
        + dirB * (cosB * 0.090 * 0.54)
        + dirC * (cosC * 0.035 * 0.38)
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
    _geometry.position.xy += horizontal * edge;
    _geometry.position.z += height * edge;
    _geometry.normal = normalize(float3(-slope.x * edge, -slope.y * edge, 1.0));
    """

    private static let surfaceShader = """
    #pragma arguments
    float uTime;
    float3 uShallow;
    float3 uSea;
    float3 uDeep;
    float3 uLight;
    float3 uSky;
    float3 uHorizon;
    float3 uSun;
    float3 uFog;
    float3 uSunDirection;
    float uSunStrength;
    float3 uSurfaceSize;
    float3 uCoordinateOffset;
    float uShoreline;
    float uIslandScale;
    float3 uBoatPosition;
    float3 uBoatHeading;
    float uBoatSpeed;
    float3 uBoatSize;
    float uBoatPresence;
    float3 uBoatReflectionColor;
    float uMicroNormalScale;
    #pragma body
    float2 localP = (_surface.diffuseTexcoord - 0.5) * uSurfaceSize.xy;
    float2 p = localP + uCoordinateOffset.xy;
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    \(waveSpectrumShader)
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
    float surfaceEdge = edgeX * edgeY;
    height *= surfaceEdge;
    slope *= surfaceEdge;
    float pixelFootprint = max(length(dfdx(p)), length(dfdy(p)));
    float macroVisibility = 1.0 - smoothstep(0.85, 4.20, pixelFootprint);
    float rippleVisibility = 1.0 - smoothstep(0.08, 0.52, pixelFootprint);
    // Relative range gives every ocean layout the same near-to-horizon LOD.
    float surfaceRadius = max(min(uSurfaceSize.x, uSurfaceSize.y) * 0.5, 1.0);
    float normalizedViewRange = length(
        float2(localP.x * 0.72, localP.y)
    ) / surfaceRadius;
    float nearField = 1.0 - smoothstep(0.18, 0.72, normalizedViewRange);
    float midField = 1.0 - smoothstep(0.62, 0.96, normalizedViewRange);
    float horizonField = smoothstep(0.60, 0.98, normalizedViewRange);
    rippleVisibility *= mix(0.34, 1.0, nearField);
    macroVisibility *= mix(0.58, 1.0, midField);

    // Mid and fine ripples alter only the fragment normal. Three crossed
    // directions retain close-range detail without multiplying vertex cost.
    float rippleA = dot(p, float2(0.829, 0.559)) * 1.82 - uTime * 1.18;
    float rippleB = dot(p, float2(-0.616, 0.788)) * 2.66 - uTime * 1.47;
    float rippleC = dot(p, float2(0.225, 0.974)) * 4.85 - uTime * 2.05;
    float detailCalm = mix(
        0.68,
        1.0,
        smoothstep(10.0, 34.0, distanceFromIsland)
    );
    float2 detailSlope = (
        float2(0.829, 0.559) * (cos(rippleA) * 0.032)
        + float2(-0.616, 0.788) * (cos(rippleB) * 0.023)
        + float2(0.225, 0.974) * (cos(rippleC) * 0.010)
    ) * detailCalm * surfaceEdge * uMicroNormalScale * rippleVisibility
        * mix(0.72, 1.14, nearField);
    float3 worldUp = normalize(
        (scn_frame.viewTransform * float4(0.0, 1.0, 0.0, 0.0)).xyz
    );
    float3 detailedNormal = normalize(
        _surface.normal
        - _surface.tangent * detailSlope.x
        - _surface.bitangent * detailSlope.y
    );
    float3 waterNormal = normalize(mix(
        worldUp,
        detailedNormal,
        mix(0.38, 1.0, macroVisibility)
    ));
    _surface.normal = waterNormal;

    // The shoreline shape doubles as a light-weight bathymetry map. In scenes
    // without an island, a gentler radial depth keeps the same palette without
    // accidentally painting a false shoreline beneath the boat.
    float openWaterDepth = 5.0 + smoothstep(0.0, 90.0, distanceFromIsland) * 13.0;
    float waterDepth = openWaterDepth;
    float shoreAngle = 0.0;
    float shoreDistance = 1000.0;
    if (uShoreline > 0.5) {
        shoreAngle = atan2(
            p.y / (9.10 * uIslandScale) + 0.00001,
            p.x / (13.10 * uIslandScale) + 0.00001
        );
        float shorelineRipple = sin(shoreAngle * 3.0 + 0.45) * 0.045
            + sin(shoreAngle * 7.0 - 0.82) * 0.026
            + sin(shoreAngle * 11.0 + 1.30) * 0.012;
        float shorelineShift = sin(shoreAngle * 5.0 + 0.91) * 0.018;
        float shorelineScale = 0.955 * (1.0 + shorelineRipple + shorelineShift);
        float ellipseRadius = length(float2(
            p.x / (13.10 * uIslandScale),
            p.y / (9.10 * uIslandScale)
        ));
        shoreDistance = (ellipseRadius - shorelineScale) * 10.8 * uIslandScale;
        waterDepth = max(0.12, shoreDistance * 0.72 + 0.12);
    }

    // Red and green wavelengths fall away first as the optical path grows;
    // blue-green scatter remains, producing depth without a dark overlay.
    float3 transmission = exp(
        -float3(0.155, 0.061, 0.027) * min(waterDepth, 24.0)
    );
    float3 filteredWater = uDeep + (uShallow - uDeep) * transmission;
    float3 waterBody = mix(
        uShallow,
        uSea,
        smoothstep(0.35, 4.6, waterDepth)
    );
    waterBody = mix(waterBody, uDeep, smoothstep(4.0, 20.0, waterDepth) * 0.82);
    float3 col = mix(waterBody, filteredWater, 0.46);
    if (uShoreline > 0.5) {
        float coastalLift = 1.0 - smoothstep(0.0, 11.0, max(shoreDistance, 0.0));
        col = mix(col, uShallow, coastalLift * 0.22);
    }

    float2 shadedSlope = slope * mix(0.30, 1.0, macroVisibility)
        + detailSlope * 2.2;
    float directionalShade = clamp(
        0.50 + dot(shadedSlope, float2(-5.2, 6.4)),
        0.0,
        1.0
    );
    col *= 0.82 + directionalShade * 0.32;

    float trough = 1.0 - smoothstep(-0.15, 0.005, height);
    float crest = smoothstep(0.045, 0.180, height);
    float elevationVisibility = mix(0.24, 1.0, macroVisibility);
    col = mix(col, uDeep, trough * 0.16 * elevationVisibility);
    col = mix(col, uShallow, crest * 0.14 * elevationVisibility);

    // Fresnel reflection is a sky gradient rather than a single cyan wash.
    // A warm, narrow sun lobe shares the same normal and therefore travels
    // across both long swells and tiny ripples as one coherent highlight.
    float3 viewDirection = normalize(_surface.view);
    float viewFacing = clamp(dot(waterNormal, viewDirection), 0.0, 1.0);
    float fresnel = 0.025 + 0.975 * pow(1.0 - viewFacing, 5.0);
    float3 reflectionDirection = reflect(-viewDirection, waterNormal);
    float skyHeight = clamp(
        dot(reflectionDirection, worldUp) * 0.72 + 0.36,
        0.0,
        1.0
    );
    float3 reflectedSky = mix(uHorizon, uSky, smoothstep(0.08, 0.88, skyHeight));
    col = mix(col, reflectedSky, 0.085 + fresnel * 0.60);

    // Broad facets borrow sky color when they turn toward the light and expose
    // deeper water on the opposing face. The variation follows displaced waves,
    // so it cannot detach into a decorative surface pattern.
    float2 sunAcrossWater = float2(-uSunDirection.x, uSunDirection.z);
    sunAcrossWater /= max(length(sunAcrossWater), 0.001);
    float sunwardFacet = clamp(
        0.5 + dot(slope, sunAcrossWater) * 9.4,
        0.0,
        1.0
    );
    float facetLift = smoothstep(0.53, 0.74, sunwardFacet);
    float facetShade = 1.0 - smoothstep(0.27, 0.48, sunwardFacet);
    float facetVisibility = mix(0.42, 1.0, macroVisibility)
        * (1.0 - horizonField * 0.72);
    float3 facetSky = mix(uHorizon, uSky, 0.32);
    col = mix(col, facetSky, facetLift * facetVisibility * 0.120);
    col = mix(col, uDeep, facetShade * facetVisibility * 0.085);

    float3 sunDirection = normalize(
        (scn_frame.viewTransform * float4(uSunDirection, 0.0)).xyz
    );
    float sunFacing = max(
        dot(waterNormal, normalize(viewDirection + sunDirection)),
        0.0
    );
    float sunBroad = pow(sunFacing, 48.0);
    float sunCore = pow(sunFacing, 192.0);
    float glintA = 0.5 + 0.5 * sin(
        dot(p, float2(1.47, -1.91)) + sin(p.y * 0.19) * 1.7 - uTime * 1.46
    );
    float glintB = 0.5 + 0.5 * sin(
        dot(p, float2(0.73, 2.31)) + sin(p.x * 0.23) * 1.3 + uTime * 1.13
    );
    float glintBreakup = 0.02 + 0.98 * smoothstep(0.38, 0.92, glintA * glintB);
    col += uSun * uSunStrength
        * (sunBroad * 0.015 + sunCore * glintBreakup * 0.32);

    // Only sufficiently high, steep and broken crests produce white water.
    // This removes the repeating bright lines that made the former surface
    // read as a patterned plane.
    float crestSteepness = smoothstep(0.028, 0.058, length(slope));
    float crestBreakup = 0.5 + 0.5 * sin(
        dot(p, float2(0.91, 0.67))
            + sin(dot(p, float2(-0.21, 0.34))) * 1.8
            - uTime * 0.61
    );
    float crestFoam = crest * crestSteepness
        * smoothstep(0.42, 0.80, crestBreakup) * macroVisibility;
    col = mix(col, uLight, crestFoam * 0.46);

    if (uShoreline > 0.5) {
        // Two advancing shore bands and angular breakup form broad, irregular lace.
        float wash = 0.18
            + sin(shoreAngle * 5.0 - uTime * 0.58) * 0.055
            + sin(shoreAngle * 13.0 + uTime * 0.37) * 0.024;
        float shorePrimary = 1.0
            - smoothstep(0.025, 0.145, abs(shoreDistance - wash));
        float shoreSecondary = 1.0 - smoothstep(
            0.035,
            0.180,
            abs(shoreDistance - wash - 0.48)
        );
        float foamBreak = 0.5 + 0.5 * sin(
            shoreAngle * 23.0 + sin(shoreAngle * 9.0) * 1.6 - uTime * 0.84
        );
        float foamLace = 0.5 + 0.5 * sin(
            shoreAngle * 41.0 - sin(shoreAngle * 17.0) * 1.1 + uTime * 0.56
        );
        float fragments = max(
            smoothstep(0.38, 0.76, foamBreak),
            smoothstep(0.68, 0.92, foamLace) * 0.55
        );
        float waterSide = smoothstep(-0.03, 0.08, shoreDistance);
        float shoreFoam = min(shorePrimary + shoreSecondary * 0.38, 1.0)
            * fragments * waterSide;
        col = mix(col, uLight, shoreFoam * 0.76);
    }

    // Boat uniforms use ocean-plane coordinates: (world X, -world Z). A soft
    // underwater footprint and narrow meniscus keep the hull attached to the
    // surface even at rest; both scale with the actual boat used by the scene.
    float2 boatHeading = uBoatHeading.xy;
    boatHeading /= max(length(boatHeading), 0.001);
    float2 fromBoat = p - uBoatPosition.xy;
    float boatLongitudinal = dot(fromBoat, boatHeading);
    float boatLateral = dot(fromBoat, float2(-boatHeading.y, boatHeading.x));
    float halfHullLength = max(uBoatSize.x * 0.5, 0.001);
    float halfHullBeam = max(uBoatSize.y * 0.5, 0.001);
    if (uBoatPresence > 0.5) {
        float hullDistance = length(float2(
            boatLongitudinal / halfHullLength,
            boatLateral / halfHullBeam
        ));
        float submergedShadow = 1.0 - smoothstep(0.62, 1.20, hullDistance);
        float meniscus = 1.0 - smoothstep(0.035, 0.18, abs(hullDistance - 1.0));
        float meniscusBreak = 0.72 + 0.28 * sin(
            boatLongitudinal * 8.1 - boatLateral * 10.7 + uTime * 0.34
        );
        float reflectedHull = smoothstep(0.70, 1.02, hullDistance)
            * (1.0 - smoothstep(1.02, 1.72, hullDistance));
        float reflectionBreak = smoothstep(
            0.28,
            0.82,
            0.5 + 0.5 * sin(
                boatLongitudinal * 5.7 + boatLateral * 9.3
                    + height * 18.0 - uTime * 0.24
            )
        );
        col = mix(col, uDeep, submergedShadow * 0.13 * surfaceEdge);
        col = mix(
            col,
            uBoatReflectionColor,
            reflectedHull * (0.035 + reflectionBreak * 0.070) * surfaceEdge
        );
        col = mix(col, uLight, meniscus * meniscusBreak * 0.10 * surfaceEdge);
    }

    // Keep the wake below foam contrast: it is a short veil of aerated water
    // with two broken divergent arms, never a row of detached particles.
    if (uBoatSpeed > 0.08) {
        float wakeOriginOffset = max(halfHullLength * 0.72, 0.18);
        float2 wakeOrigin = uBoatPosition.xy - boatHeading * wakeOriginOffset;
        float2 fromWake = p - wakeOrigin;
        float aft = -dot(fromWake, boatHeading);
        float signedLateral = dot(fromWake, float2(-boatHeading.y, boatHeading.x));
        float wakeStrength = smoothstep(0.08, 1.60, uBoatSpeed);
        float wakeLength = mix(1.6, 3.6, wakeStrength);
        if (aft > 0.0 && aft < wakeLength) {
            float wakeAge = clamp(aft / wakeLength, 0.0, 1.0);
            float remainingWake = 1.0 - wakeAge;
            float lengthFade = smoothstep(0.04, 0.38, aft)
                * remainingWake * remainingWake;
            float slowFlow = 0.5 + 0.5 * sin(
                aft * 1.35 + signedLateral * 1.9 - uTime * 0.62
            );
            float centerDrift = (slowFlow - 0.5) * mix(0.04, 0.10, wakeAge);
            float wakeWidth = mix(0.10, 0.16, wakeStrength) + aft * 0.018;
            float centerChurn = 1.0 - smoothstep(
                wakeWidth,
                wakeWidth + 0.14,
                abs(signedLateral - centerDrift)
            );
            // Dense prop wash belongs only at the stern. Farther back, the
            // energy separates into two divergent arms instead of a white strip.
            float centerTail = 1.0 - smoothstep(0.16, 0.52, wakeAge);
            float centerBreak = smoothstep(
                0.34,
                0.82,
                0.5 + 0.5 * sin(
                    aft * 5.7 + signedLateral * 3.8 - uTime * 2.1
                )
            );
            centerChurn *= centerTail * (0.30 + centerBreak * 0.70);
            float armCenter = 0.07 + aft * 0.22;
            float armDistance = abs(abs(signedLateral) - armCenter);
            float armWidth = mix(0.035, 0.080, wakeAge);
            float divergentArms = 1.0 - smoothstep(
                armWidth,
                armWidth + 0.105,
                armDistance
            );
            float armBreak = 0.5 + 0.5 * sin(
                aft * 5.1 - abs(signedLateral) * 7.3 - uTime * 1.18
            );
            divergentArms *= smoothstep(0.04, 0.18, aft)
                * (0.32 + smoothstep(0.30, 0.84, armBreak) * 0.68);
            float disturbance = max(
                centerChurn * 0.58,
                divergentArms * 0.84
            ) * lengthFade * wakeStrength * surfaceEdge;
            float turbulence = 0.5 + 0.5 * sin(
                aft * 2.35 + signedLateral * 4.7
                    + sin(aft * 0.83) * 1.15 - uTime * 0.91
            );
            float aeration = disturbance * mix(0.34, 0.72, turbulence);
            col = mix(col, uLight, aeration * 0.22);
        }
    }

    float samplingHaze = (1.0 - macroVisibility) * 0.08;
    col = mix(
        col,
        uFog,
        min(horizonField * 0.58 + samplingHaze, 0.66)
    );
    _surface.diffuse = float4(clamp(col, 0.0, 1.0), 1.0);
    """

    static func makeScene(
        layout: Layout = .homeIsland,
        appearance: Appearance = .daylight,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale,
        nativeMetalRollout: MetalOceanProgram.RolloutScene
    ) -> HomeIslandOceanScene {
        let root = SCNNode()
        root.name = layout.rootName

        let plane = SCNPlane(width: layout.width, height: layout.depth)
        plane.widthSegmentCount = layout.widthSegments
        plane.heightSegmentCount = layout.depthSegments
        let material = SCNMaterial()
        material.name = "home-island-ocean-material"
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: 0x168BA1)
        material.isDoubleSided = true
        let fallbackShaderModifiers: [SCNShaderModifierEntryPoint: String] = [
            .geometry: geometryShader,
            .surface: surfaceShader,
        ]
        if let nativeProgram = MetalOceanProgram.make(rolloutScene: nativeMetalRollout) {
            material.program = nativeProgram
            MetalOceanProgram.installUniforms(
                on: material,
                layout: layout,
                appearance: appearance,
                islandScale: islandScale
            )
            MetalOceanProgram.installRuntimeFallback(
                for: nativeProgram,
                on: material,
                shaderModifiers: fallbackShaderModifiers
            )
        } else {
            material.shaderModifiers = fallbackShaderModifiers
        }
        material.setValue(NSNumber(value: currentTime), forKey: "uTime")
        material.setValue(linearColorVector(appearance.shallow), forKey: "uShallow")
        material.setValue(linearColorVector(appearance.sea), forKey: "uSea")
        material.setValue(linearColorVector(appearance.deep), forKey: "uDeep")
        material.setValue(linearColorVector(appearance.light), forKey: "uLight")
        material.setValue(linearColorVector(appearance.sky), forKey: "uSky")
        material.setValue(linearColorVector(appearance.horizon), forKey: "uHorizon")
        material.setValue(linearColorVector(appearance.sun), forKey: "uSun")
        material.setValue(linearColorVector(appearance.fog), forKey: "uFog")
        material.setValue(appearance.sunDirection, forKey: "uSunDirection")
        material.setValue(NSNumber(value: appearance.sunStrength), forKey: "uSunStrength")
        material.setValue(
            SCNVector3(Float(layout.width), Float(layout.depth), 0),
            forKey: "uSurfaceSize"
        )
        material.setValue(SCNVector3(layout.centerX, 0, 0), forKey: "uCoordinateOffset")
        material.setValue(
            NSNumber(value: layout.includesShoreline ? Float(1) : Float(0)),
            forKey: "uShoreline"
        )
        material.setValue(NSNumber(value: islandScale), forKey: "uIslandScale")
        material.setValue(SCNVector3Zero, forKey: "uBoatPosition")
        material.setValue(SCNVector3(0, 1, 0), forKey: "uBoatHeading")
        material.setValue(NSNumber(value: Float(0)), forKey: "uBoatSpeed")
        material.setValue(SCNVector3Zero, forKey: "uBoatSize")
        material.setValue(NSNumber(value: Float(0)), forKey: "uBoatPresence")
        material.setValue(
            linearColorVector(0xA6B7AF),
            forKey: "uBoatReflectionColor"
        )
        material.setValue(
            NSNumber(value: MetalRenderingProfile.current.oceanMicroNormalScale),
            forKey: "uMicroNormalScale"
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
        underlayMaterial.diffuse.contents = UIColor(rgb: 0x07536E)
        underlayMaterial.isDoubleSided = true
        underlayGeometry.firstMaterial = underlayMaterial
        let underlay = SCNNode(geometry: underlayGeometry)
        underlay.name = "home-island-ocean-underlay"
        underlay.categoryBitMask = 1 << 4
        underlay.eulerAngles.x = -.pi / 2
        // The five displacement layers can reach about 0.30 m at full swell.
        // Keep the safety layer below that entire range so a trough never
        // reveals it as a moving dark oval.
        underlay.position = SCNVector3(layout.centerX, layout.surfaceY - 0.50, 0)
        root.addChildNode(underlay)

        return HomeIslandOceanScene(root: root, animatedMaterial: material)
    }

    static func linearColorVector(_ rgb: UInt) -> SCNVector3 {
        func linear(_ byte: UInt) -> Float {
            let component = Float(byte) / 255
            guard component > 0.04045 else { return component / 12.92 }
            return powf((component + 0.055) / 1.055, 2.4)
        }

        return SCNVector3(
            linear((rgb >> 16) & 0xFF),
            linear((rgb >> 8) & 0xFF),
            linear(rgb & 0xFF)
        )
    }
}
