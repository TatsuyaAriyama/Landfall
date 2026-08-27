#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

struct LandfallOceanVertexIn {
    float3 position [[attribute(SCNVertexSemanticPosition)]];
    float3 normal [[attribute(SCNVertexSemanticNormal)]];
    float2 texcoord [[attribute(SCNVertexSemanticTexcoord0)]];
};

struct LandfallOceanNodeBuffer {
    float4x4 modelTransform;
    float4x4 modelViewProjectionTransform;
};

struct LandfallOceanUniforms {
    float time;
    float3 shallowColor;
    float3 seaColor;
    float3 deepColor;
    float3 skyColor;
    float3 horizonColor;
    float3 sunColor;
    float3 sunDirection;
    float sunStrength;
    float2 surfaceSize;
    float2 coordinateOffset;
    float microNormalScale;
    float3 lightColor;
    float3 fogColor;
    float shoreline;
    float islandScale;
    float2 boatPosition;
    float2 boatHeading;
    float boatSpeed;
    float2 boatSize;
    float boatPresence;
    float3 boatReflectionColor;
};

struct LandfallOceanVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 localPosition;
    float2 oceanPosition;
    float2 slope;
    float height;
    float3 cameraPosition;
};

struct LandfallWaveSample {
    float height;
    float2 slope;
    float2 horizontal;
};

struct LandfallWakeSample {
    float disturbance;
    float aeration;
    float2 slope;
};

struct LandfallHullSample {
    float submergedShadow;
    float meniscusLight;
    float reflectedHull;
    float reflectionBreakup;
    float bowDisturbance;
    float bowAeration;
    float2 slope;
};

struct LandfallBoatFrame {
    float2 heading;
    float2 across;
    float longitudinal;
    float lateral;
    float halfLength;
    float halfBeam;
    float speed;
};

static inline LandfallWaveSample landfallSampleWaves(
    float2 p,
    float time,
    float includesShoreline)
{
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float coastalCalm = mix(
        0.36,
        1.0,
        smoothstep(10.0, 34.0, distanceFromIsland)
    );
    float calm = mix(0.72, coastalCalm, saturate(includesShoreline));

    constexpr float2 dirA = float2(0.342, 0.940);
    constexpr float2 dirB = float2(-0.766, 0.643);
    constexpr float2 dirC = float2(0.906, 0.423);
    constexpr float2 dirD = float2(-0.259, 0.966);
    constexpr float2 dirE = float2(0.643, -0.766);
    float basePhaseA = dot(p, dirA) * 0.105 - time * 0.42;
    float basePhaseB = dot(p, dirB) * 0.155 - time * 0.36 + 1.70;
    float phaseC = dot(p, dirC) * 0.340 - time * 0.78 + 0.45;
    float phaseD = dot(p, dirD) * 0.720 - time * 1.22 + 2.10;
    float phaseE = dot(p, dirE) * 1.250 - time * 1.68 + 0.90;
    float sinC = sin(phaseC);
    float sinD = sin(phaseD);
    float sinE = sin(phaseE);
    float phaseA = basePhaseA + sinC * 0.34 + sinD * 0.10;
    float phaseB = basePhaseB - sinD * 0.26 + sinE * 0.08;
    float cosA = cos(phaseA);
    float cosB = cos(phaseB);
    float cosC = cos(phaseC);
    float cosD = cos(phaseD);
    float cosE = cos(phaseE);

    float height = (
        sin(phaseA) * 0.171
        + sin(phaseB) * 0.104
        + sinC * 0.041
        + sinD * 0.016
        + sinE * 0.006
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
        gradientA * (cosA * 0.171)
        + gradientB * (cosB * 0.104)
        + dirC * (cosC * 0.041 * 0.340)
        + dirD * (cosD * 0.016 * 0.720)
        + dirE * (cosE * 0.006 * 1.250)
    ) * calm;
    float2 horizontal = (
        dirA * (cosA * 0.171 * 0.72)
        + dirB * (cosB * 0.104 * 0.64)
        + dirC * (cosC * 0.041 * 0.44)
    ) * calm;
    return {height, slope, horizontal};
}

static inline LandfallBoatFrame landfallBoatFrame(
    float2 p,
    constant LandfallOceanUniforms& ocean)
{
    float2 heading = ocean.boatHeading / max(length(ocean.boatHeading), 0.001);
    float2 across = float2(-heading.y, heading.x);
    float2 fromBoat = p - ocean.boatPosition;
    return {
        heading,
        across,
        dot(fromBoat, heading),
        dot(fromBoat, across),
        max(ocean.boatSize.x * 0.5, 0.001),
        max(ocean.boatSize.y * 0.5, 0.001),
        smoothstep(0.08, 1.60, ocean.boatSpeed)
    };
}

static inline LandfallWakeSample landfallSampleWake(
    constant LandfallOceanUniforms& ocean,
    LandfallBoatFrame boat)
{
    if (ocean.boatPresence <= 0.5 || ocean.boatSpeed <= 0.08) {
        return {0.0, 0.0, float2(0.0)};
    }

    // Begin just inside the stern so the hull hides the overlap and the first
    // visible wake fragment cannot detach from the water leaving the transom.
    float sternOverlap = min(boat.halfLength * 0.14, 0.18);
    float aft = -(boat.longitudinal + boat.halfLength - sternOverlap);
    float wakeLength = mix(1.6, 3.6, boat.speed);
    if (aft <= 0.0 || aft >= wakeLength) {
        return {0.0, 0.0, float2(0.0)};
    }

    float age = saturate(aft / wakeLength);
    float remaining = 1.0 - age;
    float lengthFade = smoothstep(0.04, 0.38, aft) * remaining * remaining;
    float flowPhase = aft * 1.35 + boat.lateral * 1.9 - ocean.time * 0.62;
    float centerDrift = sin(flowPhase) * 0.5 * mix(0.04, 0.10, age);
    float wakeWidth = mix(
        max(boat.halfBeam * 0.20, 0.08),
        max(boat.halfBeam * 0.32, 0.14),
        boat.speed
    ) + aft * 0.018;
    float centerChurn = 1.0 - smoothstep(
        wakeWidth,
        wakeWidth + 0.14,
        abs(boat.lateral - centerDrift)
    );
    float centerTail = 1.0 - smoothstep(0.16, 0.52, age);
    float centerBreak = smoothstep(
        0.34,
        0.82,
        0.5 + 0.5 * sin(aft * 5.7 + boat.lateral * 3.8 - ocean.time * 2.1)
    );
    centerChurn *= centerTail * (0.30 + centerBreak * 0.70);

    // Continue the bow shoulders from the outer hull rather than spawning two
    // decorative lines down the propeller centreline.
    float armCenter = boat.halfBeam * 1.10 + aft * 0.21;
    float armDistance = abs(abs(boat.lateral) - armCenter);
    float armWidth = mix(
        max(boat.halfBeam * 0.08, 0.035),
        max(boat.halfBeam * 0.17, 0.080),
        age
    );
    float divergentArms = 1.0 - smoothstep(
        armWidth,
        armWidth + max(boat.halfBeam * 0.23, 0.085),
        armDistance
    );
    float armPhase = aft * 5.1 - abs(boat.lateral) * 7.3 - ocean.time * 1.18;
    float armBreak = 0.5 + 0.5 * sin(armPhase);
    divergentArms *= smoothstep(0.04, 0.18, aft)
        * (0.32 + smoothstep(0.30, 0.84, armBreak) * 0.68);

    float disturbance = max(centerChurn * 0.58, divergentArms * 0.84)
        * lengthFade * boat.speed;
    float turbulencePhase = aft * 2.35 + boat.lateral * 4.7
        + sin(aft * 0.83) * 1.15 - ocean.time * 0.91;
    float turbulence = 0.5 + 0.5 * sin(turbulencePhase);
    float bubbleCells = (0.5 + 0.5 * sin(turbulencePhase * 1.83 + boat.lateral * 5.1))
        * (0.5 + 0.5 * cos(armPhase * 1.37 - aft * 3.2));
    float bubbleBreakup = smoothstep(0.30, 0.76, bubbleCells);
    float aeration = disturbance
        * mix(0.06, 0.70, bubbleBreakup)
        * mix(0.72, 1.0, turbulence);
    float lateralSign = boat.lateral < 0.0 ? -1.0 : 1.0;
    float2 slope = (
        boat.across * lateralSign * cos(armPhase) * 0.100
        + boat.heading * sin(turbulencePhase) * 0.055
    ) * disturbance;
    return {disturbance, aeration, slope};
}

static inline LandfallHullSample landfallSampleHullContact(
    float waveHeight,
    constant LandfallOceanUniforms& ocean,
    LandfallBoatFrame boat)
{
    if (ocean.boatPresence <= 0.5) {
        return {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, float2(0.0)};
    }

    float2 ellipsePosition = float2(
        boat.longitudinal / boat.halfLength,
        boat.lateral / boat.halfBeam
    );
    float hullDistance = max(length(ellipsePosition), 0.001);
    float submergedShadow = 1.0 - smoothstep(0.62, 1.20, hullDistance);
    float meniscus = 1.0 - smoothstep(0.035, 0.18, abs(hullDistance - 1.0));
    float contactPhase = boat.longitudinal * 8.1
        - boat.lateral * 10.7 + ocean.time * 0.34;
    float meniscusLight = meniscus * (0.72 + 0.28 * sin(contactPhase));
    float reflectedHull = smoothstep(0.70, 1.02, hullDistance)
        * (1.0 - smoothstep(1.02, 1.72, hullDistance));
    float reflectionBreakup = smoothstep(
        0.28,
        0.82,
        0.5 + 0.5 * sin(
            boat.longitudinal * 5.7 + boat.lateral * 9.3
                + waveHeight * 18.0 - ocean.time * 0.24
        )
    );

    // The normalized ellipse gradient points away from the hull at every angle.
    // A compact pressure ripple bends the water there, with extra energy at the bow.
    float2 ellipseGradient = boat.heading
            * (boat.longitudinal / (
                boat.halfLength * boat.halfLength * hullDistance
            ))
        + boat.across * (boat.lateral / (
            boat.halfBeam * boat.halfBeam * hullDistance
        ));
    float2 outward = ellipseGradient / max(length(ellipseGradient), 0.001);
    float bowFacing = smoothstep(
        -0.18,
        0.82,
        boat.longitudinal / boat.halfLength
    );
    float pressurePhase = (hullDistance - 1.0) * 13.0
        + contactPhase * 0.23 - ocean.time * mix(0.28, 0.72, boat.speed);
    float pressureStrength = meniscus
        * mix(0.022, 0.072, boat.speed)
        * mix(0.58, 1.0, bowFacing);
    float2 slope = outward * (cos(pressurePhase) * pressureStrength);

    float bowAft = boat.halfLength - boat.longitudinal;
    float hullRun = max(boat.halfLength * 2.0, 0.001);
    float bowProgress = saturate(bowAft / hullRun);
    float shoulderCenter = boat.halfBeam * 0.12 + bowAft * 0.21;
    float shoulderWidth = mix(
        max(boat.halfBeam * 0.055, 0.018),
        max(boat.halfBeam * 0.105, 0.042),
        bowProgress
    );
    float shoulderDistance = abs(abs(boat.lateral) - shoulderCenter);
    float shoulder = 1.0 - smoothstep(
        shoulderWidth,
        shoulderWidth + max(boat.halfBeam * 0.16, 0.060),
        shoulderDistance
    );
    float shoulderSpan = smoothstep(-0.05, 0.10, bowAft)
        * (1.0 - smoothstep(hullRun * 0.92, hullRun * 1.08, bowAft))
        * smoothstep(0.88, 1.04, hullDistance);
    float shoulderPhase = bowAft * 5.1
        - abs(boat.lateral) * 7.3 - ocean.time * 1.18;
    float shoulderBreak = 0.34 + smoothstep(
        0.30,
        0.84,
        0.5 + 0.5 * sin(shoulderPhase)
    ) * 0.66;
    float bowDisturbance = shoulder * shoulderSpan * shoulderBreak * boat.speed;
    float bowAeration = bowDisturbance
        * mix(0.62, 0.14, bowProgress)
        * smoothstep(0.38, 0.78, 0.5 + 0.5 * sin(shoulderPhase * 1.61));
    float lateralSign = boat.lateral < 0.0 ? -1.0 : 1.0;
    slope += (
        boat.across * lateralSign * cos(shoulderPhase) * 0.072
        + boat.heading * sin(shoulderPhase) * 0.030
    ) * bowDisturbance;
    return {
        submergedShadow,
        meniscusLight,
        reflectedHull,
        reflectionBreakup,
        bowDisturbance,
        bowAeration,
        slope
    };
}

vertex LandfallOceanVertexOut landfallOceanVertex(
    LandfallOceanVertexIn in [[stage_in]],
    constant SCNSceneBuffer& scn_frame [[buffer(0)]],
    constant LandfallOceanNodeBuffer& scn_node [[buffer(1)]],
    constant LandfallOceanUniforms& vertexOcean [[buffer(2)]])
{
    float2 localPosition = in.position.xy;
    float2 oceanPosition = localPosition + vertexOcean.coordinateOffset;
    LandfallWaveSample waves = landfallSampleWaves(
        oceanPosition,
        vertexOcean.time,
        vertexOcean.shoreline
    );

    float edgeX = 1.0 - smoothstep(
        vertexOcean.surfaceSize.x * 0.43,
        vertexOcean.surfaceSize.x * 0.50,
        abs(localPosition.x)
    );
    float edgeY = 1.0 - smoothstep(
        vertexOcean.surfaceSize.y * 0.43,
        vertexOcean.surfaceSize.y * 0.50,
        abs(localPosition.y)
    );
    float edge = edgeX * edgeY;
    float3 displaced = in.position;
    displaced.xy += waves.horizontal * edge;
    displaced.z += waves.height * edge;
    float3 localNormal = normalize(float3(-waves.slope * edge, 1.0));

    LandfallOceanVertexOut out;
    out.position = scn_node.modelViewProjectionTransform * float4(displaced, 1.0);
    out.worldPosition = (scn_node.modelTransform * float4(displaced, 1.0)).xyz;
    out.worldNormal = normalize((scn_node.modelTransform * float4(localNormal, 0.0)).xyz);
    out.localPosition = localPosition;
    out.oceanPosition = oceanPosition;
    out.slope = waves.slope * edge;
    out.height = waves.height * edge;
    // SceneKit supplies SCNSceneBuffer to the vertex stage. Passing the camera
    // through avoids requesting an unbound custom `frame` attachment from each
    // fragment function, which otherwise leaves only the safety underlay visible.
    out.cameraPosition = scn_frame.inverseViewTransform[3].xyz;
    return out;
}

static inline half4 landfallShadeOcean(
    LandfallOceanVertexOut in,
    constant LandfallOceanUniforms& ocean,
    float detailQuality)
{
    float2 p = in.oceanPosition;
    float pixelFootprint = max(length(dfdx(p)), length(dfdy(p)));
    float macroVisibility = 1.0 - smoothstep(0.85, 4.20, pixelFootprint);
    float rippleVisibility = 1.0 - smoothstep(0.08, 0.52, pixelFootprint);
    // Relative range gives every ocean layout the same near-to-horizon LOD.
    float surfaceRadius = max(min(ocean.surfaceSize.x, ocean.surfaceSize.y) * 0.5, 1.0);
    float normalizedViewRange = length(
        float2(in.localPosition.x * 0.72, in.localPosition.y)
    ) / surfaceRadius;
    float nearField = 1.0 - smoothstep(0.18, 0.72, normalizedViewRange);
    float midField = 1.0 - smoothstep(0.62, 0.96, normalizedViewRange);
    float horizonField = smoothstep(0.60, 0.98, normalizedViewRange);
    rippleVisibility *= mix(0.34, 1.0, nearField);
    macroVisibility *= mix(0.58, 1.0, midField);
    LandfallBoatFrame boat = landfallBoatFrame(p, ocean);
    LandfallWakeSample wake = landfallSampleWake(ocean, boat);
    LandfallHullSample hull = landfallSampleHullContact(in.height, ocean, boat);
    float rippleWarp = sin(dot(p, float2(0.173, -0.241)) - ocean.time * 0.31);
    float rippleA = dot(p, float2(0.829, 0.559)) * 1.82
        - ocean.time * 1.18 + rippleWarp * 0.28;
    float rippleB = dot(p, float2(-0.616, 0.788)) * 2.66
        - ocean.time * 1.47 - rippleWarp * 0.36;
    float rippleC = dot(p, float2(0.225, 0.974)) * 4.85
        - ocean.time * 2.05 + rippleWarp * 0.52;
    float2 capillarySlope = float2(0.0);
    if (detailQuality > 0.75) {
        float visibility = 1.0 - smoothstep(0.14, 0.48, pixelFootprint * 8.4);
        constexpr float2 capillaryDirectionA = float2(-0.952, 0.306);
        constexpr float2 capillaryDirectionB = float2(0.391, 0.920);
        float rippleD = dot(p, capillaryDirectionA) * 8.4
            - ocean.time * 2.72 - rippleWarp * 0.81;
        float rippleE = dot(p, capillaryDirectionB) * 10.7
            - ocean.time * 3.16 + rippleWarp * 0.54 - sin(rippleD) * 0.18;
        float tierBlend = smoothstep(0.75, 1.0, detailQuality);
        float interference = mix(
            0.72,
            1.0,
            0.5 + 0.5 * sin(rippleD - rippleE)
        );
        capillarySlope = (
            capillaryDirectionA * (cos(rippleD) * 0.0044)
            + capillaryDirectionB * (cos(rippleE) * 0.0032)
        ) * visibility * tierBlend * interference;
    }
    float2 detailSlope = (
        float2(0.829, 0.559) * (cos(rippleA) * 0.032)
        + float2(-0.616, 0.788) * (cos(rippleB) * 0.023)
        + float2(0.225, 0.974) * (cos(rippleC) * 0.010)
        + capillarySlope
    ) * ocean.microNormalScale * rippleVisibility * mix(0.72, 1.14, nearField);
    detailSlope += wake.slope * macroVisibility * mix(0.76, 1.0, detailQuality);
    detailSlope += hull.slope * macroVisibility;
    float3 detailedNormal = normalize(
        in.worldNormal + float3(-detailSlope.x, 0.0, detailSlope.y)
    );
    float3 normal = normalize(mix(
        float3(0.0, 1.0, 0.0),
        detailedNormal,
        mix(0.38, 1.0, macroVisibility)
    ));

    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float waterDepth = 5.0 + smoothstep(0.0, 90.0, distanceFromIsland) * 13.0;
    float shoreAngle = 0.0;
    float shoreDistance = 1000.0;
    if (ocean.shoreline > 0.5) {
        shoreAngle = atan2(
            p.y / (9.10 * ocean.islandScale) + 0.00001,
            p.x / (13.10 * ocean.islandScale) + 0.00001
        );
        float shorelineRipple = sin(shoreAngle * 3.0 + 0.45) * 0.045
            + sin(shoreAngle * 7.0 - 0.82) * 0.026
            + sin(shoreAngle * 11.0 + 1.30) * 0.012;
        float shorelineShift = sin(shoreAngle * 5.0 + 0.91) * 0.018;
        float shorelineScale = 0.955 * (1.0 + shorelineRipple + shorelineShift);
        float ellipseRadius = length(float2(
            p.x / (13.10 * ocean.islandScale),
            p.y / (9.10 * ocean.islandScale)
        ));
        shoreDistance = (ellipseRadius - shorelineScale) * 10.8 * ocean.islandScale;
        waterDepth = max(0.12, shoreDistance * 0.72 + 0.12);
    }

    float3 transmission = exp(-float3(0.155, 0.061, 0.027) * min(waterDepth, 24.0));
    float3 filteredWater = ocean.deepColor + (ocean.shallowColor - ocean.deepColor) * transmission;
    float3 body = mix(ocean.shallowColor, ocean.seaColor, smoothstep(0.35, 4.6, waterDepth));
    body = mix(body, ocean.deepColor, smoothstep(4.0, 20.0, waterDepth) * 0.82);
    float3 color = mix(body, filteredWater, 0.46);
    if (ocean.shoreline > 0.5) {
        float coastalLift = 1.0 - smoothstep(0.0, 11.0, max(shoreDistance, 0.0));
        color = mix(color, ocean.shallowColor, coastalLift * 0.22);
    }
    float underwaterScatter = exp(-waterDepth * 0.16);
    color += ocean.shallowColor * underwaterScatter * 0.12;

    float2 shadedSlope = in.slope * mix(0.30, 1.0, macroVisibility)
        + detailSlope * 2.2;
    float directionalShade = saturate(0.50 + dot(shadedSlope, float2(-5.2, 6.4)));
    color *= 0.82 + directionalShade * 0.32;

    float trough = 1.0 - smoothstep(-0.15, 0.005, in.height);
    float crest = smoothstep(0.045, 0.180, in.height);
    float elevationVisibility = mix(0.24, 1.0, macroVisibility);
    color = mix(color, ocean.deepColor, trough * 0.16 * elevationVisibility);
    color = mix(color, ocean.shallowColor, crest * 0.14 * elevationVisibility);

    float3 viewDirection = normalize(in.cameraPosition - in.worldPosition);
    float fresnel = 0.025 + 0.975 * pow(1.0 - saturate(dot(normal, viewDirection)), 5.0);
    float3 reflectionDirection = reflect(-viewDirection, normal);
    float skyHeight = saturate(reflectionDirection.y * 0.72 + 0.36);
    float skyBlend = smoothstep(0.06, 0.90, skyHeight);
    float3 reflectedSky = mix(ocean.horizonColor, ocean.skyColor * 1.08, skyBlend);
    float horizonHaze = 1.0 - smoothstep(0.02, 0.34, abs(reflectionDirection.y));
    reflectedSky = mix(reflectedSky, ocean.horizonColor * 1.06, horizonHaze * 0.28);
    color = mix(color, reflectedSky, 0.12 + fresnel * 0.64);

    // A real water surface catches the bright horizon in narrow, broken facets.
    // Let the normal field form that ribbon, then widen it by a pixel derivative
    // so distant rows converge instead of aliasing into horizontal stripes.
    float horizonFootprint = max(fwidth(reflectionDirection.y) * 1.6, 0.012);
    float horizonRibbon = 1.0 - smoothstep(
        horizonFootprint,
        horizonFootprint + 0.105,
        abs(reflectionDirection.y)
    );
    float ribbonVisibility = rippleVisibility
        * mix(0.30, 1.0, nearField)
        * (1.0 - horizonField * 0.72);
    color = mix(
        color,
        ocean.horizonColor * 1.055,
        horizonRibbon * ribbonVisibility * (0.025 + fresnel * 0.055)
    );

    // Broad facets borrow sky color when they turn toward the light and expose
    // deeper water on the opposing face. The variation follows displaced waves,
    // so it cannot detach into a decorative surface pattern.
    float2 sunAcrossWater = float2(-ocean.sunDirection.x, ocean.sunDirection.z);
    sunAcrossWater /= max(length(sunAcrossWater), 0.001);
    float sunwardFacet = saturate(0.5 + dot(in.slope, sunAcrossWater) * 9.4);
    float facetLift = smoothstep(0.53, 0.74, sunwardFacet);
    float facetShade = 1.0 - smoothstep(0.27, 0.48, sunwardFacet);
    float facetVisibility = mix(0.42, 1.0, macroVisibility)
        * (1.0 - horizonField * 0.72);
    float3 facetSky = mix(ocean.horizonColor, ocean.skyColor, 0.32);
    color = mix(color, facetSky, facetLift * facetVisibility * 0.120);
    color = mix(color, ocean.deepColor, facetShade * facetVisibility * 0.085);

    float3 halfVector = normalize(viewDirection + normalize(ocean.sunDirection));
    float sunFacing = max(dot(normal, halfVector), 0.0);
    float sunShoulder = pow(sunFacing, 18.0);
    float sunBroad = pow(sunFacing, 54.0);
    float sunCore = pow(sunFacing, 192.0);
    float glintA = 0.5 + 0.5 * sin(
        dot(p, float2(1.47, -1.91)) + sin(p.y * 0.19) * 1.7 - ocean.time * 1.46
    );
    float glintB = 0.5 + 0.5 * sin(
        dot(p, float2(0.73, 2.31)) + sin(p.x * 0.23) * 1.3 + ocean.time * 1.13
    );
    float glintBreakup = 0.02 + 0.98 * smoothstep(0.38, 0.92, glintA * glintB);
    // Ultra lets the same capillary normals that bend the sky reflection gate
    // the finest sunlight facets. This keeps sparkles attached to real surface
    // orientation instead of adding an independent decorative noise layer.
    float capillaryFacing = saturate(
        0.5 + dot(capillarySlope, sunAcrossWater) * 48.0
    );
    float capillaryFootprint = max(fwidth(capillaryFacing), 0.025);
    float capillarySparkle = smoothstep(
        0.56 - capillaryFootprint,
        0.78 + capillaryFootprint,
        capillaryFacing
    );
    float ultraGlintBlend = smoothstep(0.80, 1.0, detailQuality) * nearField;
    glintBreakup *= mix(1.0, 0.34 + capillarySparkle * 0.66, ultraGlintBlend);
    float glintVisibility = rippleVisibility
        * mix(0.34, 1.0, nearField)
        * (1.0 - horizonField * 0.58);
    color += ocean.sunColor * ocean.sunStrength
        * (sunShoulder * glintBreakup * glintVisibility * 0.020
            + sunBroad * 0.018
            + sunCore * glintBreakup * 0.28);
    float forwardScatter = pow(
        saturate(dot(viewDirection, -normalize(ocean.sunDirection))),
        4.0
    );
    color += ocean.sunColor * underwaterScatter * forwardScatter * 0.035;

    float crestSteepness = smoothstep(0.028, 0.058, length(in.slope));
    float crestBreakup = 0.5 + 0.5 * sin(
        dot(p, float2(0.91, 0.67))
            + sin(dot(p, float2(-0.21, 0.34))) * 1.8
            - ocean.time * 0.61
    );
    float crestFoam = crest * crestSteepness
        * smoothstep(0.42, 0.80, crestBreakup) * macroVisibility;
    color = mix(color, ocean.lightColor, crestFoam * 0.46);

    if (ocean.shoreline > 0.5) {
        float wash = 0.18
            + sin(shoreAngle * 5.0 - ocean.time * 0.58) * 0.055
            + sin(shoreAngle * 13.0 + ocean.time * 0.37) * 0.024;
        float primary = 1.0 - smoothstep(0.025, 0.145, abs(shoreDistance - wash));
        float secondary = 1.0 - smoothstep(
            0.035,
            0.180,
            abs(shoreDistance - wash - 0.48)
        );
        float foamBreak = 0.5 + 0.5 * sin(
            shoreAngle * 23.0 + sin(shoreAngle * 9.0) * 1.6 - ocean.time * 0.84
        );
        float foamLace = 0.5 + 0.5 * sin(
            shoreAngle * 41.0 - sin(shoreAngle * 17.0) * 1.1 + ocean.time * 0.56
        );
        float fragments = max(
            smoothstep(0.38, 0.76, foamBreak),
            smoothstep(0.68, 0.92, foamLace) * 0.55
        );
        float waterSide = smoothstep(-0.03, 0.08, shoreDistance);
        float shoreFoam = min(primary + secondary * 0.38, 1.0) * fragments * waterSide;
        color = mix(color, ocean.lightColor, shoreFoam * 0.76);
    }

    if (ocean.boatPresence > 0.5) {
        color = mix(color, ocean.deepColor, hull.submergedShadow * 0.13);
        color = mix(
            color,
            ocean.boatReflectionColor,
            hull.reflectedHull * (0.035 + hull.reflectionBreakup * 0.070)
        );
        color = mix(color, ocean.lightColor, hull.meniscusLight * 0.10);
        color = mix(color, ocean.shallowColor, hull.bowDisturbance * 0.022);
        color = mix(color, ocean.lightColor, hull.bowAeration * 0.13);
    }

    if (wake.disturbance > 0.0) {
        // Disturbed water first exposes a little shallow body color; only the
        // most aerated fragments become foam. The same sample already perturbed
        // the normal above, so the wake bends reflections instead of sitting on top.
        color = mix(color, ocean.shallowColor, wake.disturbance * 0.020);
        color = mix(color, ocean.lightColor, wake.aeration * 0.15);
    }

    // Aerial perspective must finish at the same radiance as the sky behind
    // the finite mesh. Leaving even a small amount of body color at the final
    // row exposes the plane as a straight horizontal cut.
    float farAtmosphere = smoothstep(0.72, 0.97, normalizedViewRange);
    float samplingHaze = (1.0 - macroVisibility) * 0.08;
    float atmosphericHaze = saturate(farAtmosphere + samplingHaze);
    color = 1.0 - exp(-max(color, 0.0) * 1.16);
    color = mix(color, sqrt(max(color, 0.0)), 0.07);
    color = mix(color, ocean.fogColor, atmosphericHaze);
    return half4(half3(saturate(color)), 1.0h);
}

fragment half4 landfallOceanFragmentCompatible(
    LandfallOceanVertexOut in [[stage_in]],
    constant LandfallOceanUniforms& fragmentOcean [[buffer(2)]])
{
    return landfallShadeOcean(in, fragmentOcean, 0.62);
}

fragment half4 landfallOceanFragmentEnhanced(
    LandfallOceanVertexOut in [[stage_in]],
    constant LandfallOceanUniforms& fragmentOcean [[buffer(2)]])
{
    return landfallShadeOcean(in, fragmentOcean, 0.86);
}

fragment half4 landfallOceanFragmentUltra(
    LandfallOceanVertexOut in [[stage_in]],
    constant LandfallOceanUniforms& fragmentOcean [[buffer(2)]])
{
    return landfallShadeOcean(in, fragmentOcean, 1.0);
}
