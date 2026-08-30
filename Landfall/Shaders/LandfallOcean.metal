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
    float boatHeave;
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
    float breaking;
    float foamRemnant;
    float3 cameraPosition;
};

struct LandfallWaveSample {
    float height;
    float2 slope;
    float2 horizontal;
    float breaking;
    float foamRemnant;
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
    float calm = mix(0.24, coastalCalm, saturate(includesShoreline));

    constexpr float2 dirA = float2(0.342, 0.940);
    constexpr float2 dirB = float2(-0.766, 0.643);
    constexpr float2 dirC = float2(0.906, 0.423);
    constexpr float2 dirD = float2(-0.259, 0.966);
    constexpr float2 dirE = float2(0.643, -0.766);
    constexpr float2 dirF = float2(-0.940, 0.342);
    constexpr float2 dirG = float2(0.515, 0.857);
    constexpr float2 dirH = float2(0.118, -0.993);
    constexpr float2 dirI = float2(0.982, 0.190);
    float basePhaseA = dot(p, dirA) * 0.105 - time * 0.42;
    float basePhaseB = dot(p, dirB) * 0.155 - time * 0.36 + 1.70;
    float phaseC = dot(p, dirC) * 0.340 - time * 0.78 + 0.45;
    float phaseD = dot(p, dirD) * 0.720 - time * 1.22 + 2.10;
    float phaseE = dot(p, dirE) * 1.250 - time * 1.68 + 0.90;
    // Very low-frequency cross swell slowly bends the two dominant wave trains.
    // This prevents an oblique camera from compressing long, perfectly straight
    // crests into parallel horizontal bands while keeping the surface coherent.
    float phaseF = dot(p, dirF) * 0.052 - time * 0.14 + 0.30;
    float phaseG = dot(p, dirG) * 0.073 - time * 0.19 + 1.35;
    float phaseH = dot(p, dirH) * 0.310 - time * 0.27 + 2.20;
    float phaseI = dot(p, dirI) * 0.470 - time * 0.39 + 0.60;
    float sinC = sin(phaseC);
    float sinD = sin(phaseD);
    float sinE = sin(phaseE);
    float sinF = sin(phaseF);
    float sinG = sin(phaseG);
    float sinH = sin(phaseH);
    float sinI = sin(phaseI);
    float phaseA = basePhaseA + sinC * 0.20 + sinD * 0.05
        + sinF * 0.45 + sinH * 0.08 + sinI * 0.04;
    float phaseB = basePhaseB - sinD * 0.12 + sinE * 0.04
        - sinG * 0.36 - sinH * 0.05 + sinI * 0.06;
    float cosA = cos(phaseA);
    float cosB = cos(phaseB);
    float cosC = cos(phaseC);
    float cosD = cos(phaseD);
    float cosE = cos(phaseE);
    float cosF = cos(phaseF);
    float cosG = cos(phaseG);
    float cosH = cos(phaseH);
    float cosI = cos(phaseI);
    float energyPhaseA = phaseF + 1.17;
    float energyPhaseB = phaseG - 0.83;
    float energyA = 1.0 + sin(energyPhaseA) * 0.18;
    float energyB = 1.0 + sin(energyPhaseB) * 0.14;
    float2 energyGradientA = dirF * (cos(energyPhaseA) * 0.052 * 0.18);
    float2 energyGradientB = dirG * (cos(energyPhaseB) * 0.073 * 0.14);
    // A restrained Stokes-like second harmonic tightens each dominant crest
    // and broadens its trough. Height, slope and horizontal motion share the
    // same phase, so the mesh, boat response and whitewater stay coherent.
    float harmonicPhaseA = phaseA * 2.0 + 0.35;
    float harmonicPhaseB = phaseB * 2.0 - 0.62;
    float shapedA = sin(phaseA) + sin(harmonicPhaseA) * 0.18;
    float shapedB = sin(phaseB) + sin(harmonicPhaseB) * 0.13;
    float shapedDerivativeA = cosA + cos(harmonicPhaseA) * 0.36;
    float shapedDerivativeB = cosB + cos(harmonicPhaseB) * 0.26;

    float height = (
        shapedA * 0.171 * energyA
        + shapedB * 0.104 * energyB
        + sinC * 0.052
        + sinD * 0.020
        + sinE * 0.006
    ) * calm;
    float2 gradientA = (
        dirA * 0.105
        + dirC * (cosC * 0.340 * 0.20)
        + dirD * (cosD * 0.720 * 0.05)
        + dirF * (cosF * 0.052 * 0.45)
        + dirH * (cosH * 0.310 * 0.08)
        + dirI * (cosI * 0.470 * 0.04)
    );
    float2 gradientB = (
        dirB * 0.155
        - dirD * (cosD * 0.720 * 0.12)
        + dirE * (cosE * 1.250 * 0.04)
        - dirG * (cosG * 0.073 * 0.36)
        - dirH * (cosH * 0.310 * 0.05)
        + dirI * (cosI * 0.470 * 0.06)
    );
    float2 slope = (
        gradientA * (shapedDerivativeA * 0.171 * energyA)
        + energyGradientA * (shapedA * 0.171)
        + gradientB * (shapedDerivativeB * 0.104 * energyB)
        + energyGradientB * (shapedB * 0.104)
        + dirC * (cosC * 0.052 * 0.340)
        + dirD * (cosD * 0.020 * 0.720)
        + dirE * (cosE * 0.006 * 1.250)
    ) * calm;
    float2 horizontal = (
        dirA * ((cosA + cos(harmonicPhaseA) * 0.18) * 0.171 * 0.72 * energyA)
        + dirB * ((cosB + cos(harmonicPhaseB) * 0.13) * 0.104 * 0.64 * energyB)
        + dirC * (cosC * 0.052 * 0.44)
    ) * calm;
    // White water is born on the compressed, forward face of energetic wave
    // groups. Keeping this signal in the spectrum makes it travel with the
    // displaced crest instead of sliding across the surface as decorative noise.
    float compressedA = -cosA;
    float compressedB = -cosB;
    float breakingA = (1.0 - smoothstep(0.06, 0.16, abs(compressedA - 0.38)))
        * smoothstep(0.76, 0.94, sin(phaseA))
        * smoothstep(0.99, 1.14, energyA);
    float breakingB = (1.0 - smoothstep(0.07, 0.17, abs(compressedB - 0.40)))
        * smoothstep(0.78, 0.95, sin(phaseB))
        * smoothstep(0.99, 1.11, energyB) * 0.78;
    float breaking = max(breakingA, breakingB) * calm;
    // After the crest passes, a weaker lobe remains on the rear face for a
    // short phase interval. Because it uses the same phase and energy groups,
    // the residue travels with the wave instead of becoming a static decal.
    float remnantA = smoothstep(0.50, 0.84, sin(phaseA))
        * smoothstep(0.02, 0.68, cosA)
        * smoothstep(0.92, 1.11, energyA);
    float remnantB = smoothstep(0.54, 0.86, sin(phaseB))
        * smoothstep(0.03, 0.70, cosB)
        * smoothstep(0.93, 1.10, energyB) * 0.62;
    float foamRemnant = max(remnantA, remnantB) * calm;
    return {height, slope, horizontal, breaking, foamRemnant};
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
    // Follow the emission time of each parcel instead of only oscillating the
    // finished footprint in place. Fresh wash stays connected at the stern;
    // older parcels travel aft and open into short, dissolving pockets.
    float advectionSpeed = mix(0.68, 1.24, boat.speed);
    float emissionClock = ocean.time - aft / advectionSpeed;
    float parcelPulse = smoothstep(
        0.18,
        0.82,
        0.5 + 0.5 * sin(emissionClock * 2.35 + abs(boat.lateral) * 1.4)
    );
    float parcelEnvelope = mix(
        1.0,
        0.58 + parcelPulse * 0.42,
        smoothstep(0.18, 0.74, age)
    );
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
        * lengthFade * boat.speed * parcelEnvelope;
    float turbulencePhase = aft * 2.35 + boat.lateral * 4.7
        + sin(aft * 0.83) * 1.15 - ocean.time * 0.91;
    float turbulence = 0.5 + 0.5 * sin(turbulencePhase);
    float bubblePrimary = 0.5 + 0.5 * sin(
        turbulencePhase * 1.83 + boat.lateral * 5.1
    );
    float bubbleSecondary = 0.5 + 0.5 * cos(
        armPhase * 1.37 - aft * 3.2
    );
    // Entrained air forms short overlapping pockets. Multiplying both cell
    // fields outright made almost every fragment vanish on a phone display;
    // retain a sparse primary pocket while the secondary field breaks its edge.
    float bubbleCells = bubblePrimary * mix(0.28, 1.0, bubbleSecondary);
    float bubbleFilter = max(fwidth(bubbleCells) * 0.55, 0.015);
    float bubbleBreakup = smoothstep(
        0.32 - bubbleFilter,
        0.74 + bubbleFilter,
        bubbleCells
    );
    // Fresh prop wash reads as one aerated mass. As it travels aft, the same
    // advected cells become gaps, leaving separated pockets before the tail dies.
    float foamAge = smoothstep(0.10, 0.72, age);
    float pocketIntegrity = mix(
        0.66 + bubbleBreakup * 0.34,
        0.08 + bubbleBreakup * 0.92,
        foamAge
    );
    float tailDissolve = mix(
        1.0,
        smoothstep(
            0.40 - bubbleFilter,
            0.86 + bubbleFilter,
            bubbleSecondary
        ),
        smoothstep(0.48, 0.92, age)
    );
    float aeration = disturbance
        * pocketIntegrity * tailDissolve
        * mix(0.72, 1.0, turbulence);

    // The foamy core dissipates quickly, but its energy continues outward as
    // low Kelvin shoulders. They alter reflected light instead of painting
    // more white onto the water, so the wake keeps volume at viewing distance
    // without returning to a decorative V-shaped stripe.
    float shoulderCenter = boat.halfBeam * 1.28 + aft * 0.29;
    float shoulderDistance = abs(abs(boat.lateral) - shoulderCenter);
    float shoulderWidth = mix(
        max(boat.halfBeam * 0.15, 0.060),
        max(boat.halfBeam * 0.30, 0.140),
        age
    );
    float shoulderEnvelope = 1.0 - smoothstep(
        shoulderWidth,
        shoulderWidth + max(boat.halfBeam * 0.42, 0.180),
        shoulderDistance
    );
    float shoulderPhase = aft * 3.9
        - abs(boat.lateral) * 5.7 - ocean.time * 0.78;
    float shoulderBreak = 0.68 + 0.32 * sin(
        aft * 1.31 + abs(boat.lateral) * 2.2 - ocean.time * 0.29
    );
    shoulderEnvelope *= smoothstep(0.14, 0.46, aft)
        * remaining * remaining * boat.speed * shoulderBreak;
    float lateralSign = boat.lateral < 0.0 ? -1.0 : 1.0;
    float2 slope = (
        boat.across * lateralSign * cos(armPhase) * 0.100
        + boat.heading * sin(turbulencePhase) * 0.055
    ) * disturbance;
    slope += (
        boat.across * lateralSign * cos(shoulderPhase) * 0.050
        - boat.heading * sin(shoulderPhase) * 0.029
    ) * shoulderEnvelope;
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

    float longitudinalUnit = boat.longitudinal / boat.halfLength;
    float lateralUnit = boat.lateral / boat.halfBeam;
    // A symmetric ellipse leaves a rounded halo ahead of every bow. Blend a
    // broad transom into a sharper forward waterplane so shadow, reflection,
    // meniscus and pressure all follow one boat-like footprint.
    float hullExponent = mix(
        2.45,
        1.48,
        smoothstep(-0.24, 0.58, longitudinalUnit)
    );
    float hullDistance = pow(
        pow(abs(longitudinalUnit), hullExponent)
            + pow(abs(lateralUnit), hullExponent),
        1.0 / hullExponent
    );
    // Compare this fragment's displaced surface with the boat's actual heave.
    // A crest climbing the flared hull widens its contact footprint; a trough
    // narrows it. Shadow, meniscus, reflection and pressure all consume this
    // same adjusted distance so the contact cannot split into separate rings.
    float relativeSurfaceHeight = clamp(
        waveHeight - ocean.boatHeave,
        -0.12,
        0.16
    );
    float contactScale = 1.0 + relativeSurfaceHeight * 1.10;
    hullDistance = max(hullDistance / contactScale, 0.001);
    float contactLoad = smoothstep(-0.07, 0.11, relativeSurfaceHeight);
    float submergedShadow = (1.0 - smoothstep(0.62, 1.20, hullDistance))
        * mix(0.72, 1.0, contactLoad);
    float meniscus = 1.0 - smoothstep(0.035, 0.18, abs(hullDistance - 1.0));
    float contactPhase = boat.longitudinal * 8.1
        - boat.lateral * 10.7 + ocean.time * 0.34;
    float meniscusLight = meniscus
        * mix(0.48, 1.0, contactLoad)
        * (0.72 + 0.28 * sin(contactPhase));
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

    // The implicit superellipse gradient keeps pressure normals perpendicular
    // to the same asymmetric waterplane instead of falling back to an ellipse.
    float2 hullGradient = boat.heading
            * (sign(longitudinalUnit)
                * pow(max(abs(longitudinalUnit), 0.0001), hullExponent - 1.0)
                / boat.halfLength)
        + boat.across
            * (sign(lateralUnit)
                * pow(max(abs(lateralUnit), 0.0001), hullExponent - 1.0)
                / boat.halfBeam);
    float2 outward = hullGradient / max(length(hullGradient), 0.001);
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
    // Keep geometry resolution attached to the camera, not to a circle around
    // the boat. The latter projected as a soft ring of waves on portrait screens.
    float3 cameraWorldPosition = scn_frame.inverseViewTransform[3].xyz;
    float3 baseWorldPosition = (
        scn_node.modelTransform * float4(in.position, 1.0)
    ).xyz;
    float viewRange = distance(baseWorldPosition, cameraWorldPosition);
    float cameraResolved = 1.0 - smoothstep(20.0, 52.0, viewRange);
    float subjectDistance = length(oceanPosition - vertexOcean.boatPosition);
    float subjectBoost = vertexOcean.boatPresence
        * (1.0 - vertexOcean.shoreline)
        * (1.0 - smoothstep(4.0, 12.0, subjectDistance));
    float geometryVisibility = 1.0
        - (1.0 - cameraResolved) * (1.0 - subjectBoost);
    float3 displaced = in.position;
    displaced.xy += waves.horizontal * edge * geometryVisibility;
    displaced.z += waves.height * edge * geometryVisibility;
    float3 localNormal = normalize(float3(
        -waves.slope * edge * geometryVisibility,
        1.0
    ));

    LandfallOceanVertexOut out;
    out.position = scn_node.modelViewProjectionTransform * float4(displaced, 1.0);
    out.worldPosition = (scn_node.modelTransform * float4(displaced, 1.0)).xyz;
    out.worldNormal = normalize((scn_node.modelTransform * float4(localNormal, 0.0)).xyz);
    out.localPosition = localPosition;
    out.oceanPosition = oceanPosition;
    out.slope = waves.slope * edge * geometryVisibility;
    out.height = waves.height * edge * geometryVisibility;
    out.breaking = waves.breaking * edge * geometryVisibility;
    out.foamRemnant = waves.foamRemnant * edge * geometryVisibility;
    // SceneKit supplies SCNSceneBuffer to the vertex stage. Passing the camera
    // through avoids requesting an unbound custom `frame` attachment from each
    // fragment function, which otherwise leaves only the safety underlay visible.
    out.cameraPosition = cameraWorldPosition;
    return out;
}

static inline half4 landfallShadeOcean(
    LandfallOceanVertexOut in,
    constant LandfallOceanUniforms& ocean,
    float detailQuality)
{
    float2 p = in.oceanPosition;
    float2 footprintX = dfdx(p);
    float2 footprintY = dfdy(p);
    float footprintMajor = max(length(footprintX), length(footprintY));
    float footprintMinor = min(length(footprintX), length(footprintY));
    float pixelFootprint = footprintMajor;
    float projectionAnisotropy = footprintMajor / max(footprintMinor, 0.001);
    float macroVisibility = 1.0 - smoothstep(0.85, 4.20, pixelFootprint);
    float3 cameraVector = in.cameraPosition - in.worldPosition;
    float cameraDistance = length(cameraVector);
    float3 viewDirection = cameraVector / max(cameraDistance, 0.001);
    float viewElevation = saturate(viewDirection.y);
    float normalizedViewRange = saturate(cameraDistance / 64.0);
    float nearField = 1.0 - smoothstep(8.0, 24.0, cameraDistance);
    float midField = 1.0 - smoothstep(24.0, 52.0, cameraDistance);
    float horizonField = smoothstep(34.0, 64.0, cameraDistance);
    // Filter each normal octave at its own projected wavelength. The former
    // shared cutoff discarded the long 3.4 m ripple as soon as the shortest
    // 1.3 m band became undersampled, flattening every oblique voyage view.
    constexpr float2 rippleDirectionA = float2(0.829, 0.559);
    constexpr float2 rippleDirectionB = float2(-0.616, 0.788);
    constexpr float2 rippleDirectionC = float2(0.225, 0.974);
    float rippleFootprintA = max(
        abs(dot(footprintX, rippleDirectionA)),
        abs(dot(footprintY, rippleDirectionA))
    );
    float rippleFootprintB = max(
        abs(dot(footprintX, rippleDirectionB)),
        abs(dot(footprintY, rippleDirectionB))
    );
    float rippleFootprintC = max(
        abs(dot(footprintX, rippleDirectionC)),
        abs(dot(footprintY, rippleDirectionC))
    );
    float nearRippleVisibility = mix(0.34, 1.0, nearField);
    float rippleVisibilityA = (
        1.0 - smoothstep(0.42, 1.15, rippleFootprintA)
    ) * nearRippleVisibility;
    float rippleVisibilityB = (
        1.0 - smoothstep(0.28, 0.82, rippleFootprintB)
    ) * nearRippleVisibility;
    float rippleVisibilityC = (
        1.0 - smoothstep(0.12, 0.46, rippleFootprintC)
    ) * nearRippleVisibility;
    // A single surviving octave reads as a painted stripe at a grazing angle.
    // Keep the longest ripple only where a crossing octave can break its crest.
    float crossedRippleSupport = max(rippleVisibilityB, rippleVisibilityC);
    rippleVisibilityA *= mix(
        0.08,
        1.0,
        smoothstep(0.08, 0.58, crossedRippleSupport)
    );
    float rippleVisibility = max(
        rippleVisibilityA,
        max(rippleVisibilityB, rippleVisibilityC)
    );
    macroVisibility *= mix(0.58, 1.0, midField);
    // Projected long swells collapse into coherent horizontal stripes before
    // their geometry is truly undersampled. Fade their lighting contribution
    // earlier than the surface itself while retaining filtered micro normals.
    float stripeRisk = smoothstep(1.8, 4.8, projectionAnisotropy)
        * smoothstep(5.0, 36.0, cameraDistance);
    float subjectDistance = ocean.boatPresence > 0.5
        ? length(p - ocean.boatPosition)
        : cameraDistance;
    float cameraResolved = 1.0 - smoothstep(20.0, 52.0, cameraDistance);
    float subjectBoost = ocean.boatPresence * (1.0 - ocean.shoreline)
        * (1.0 - smoothstep(4.0, 12.0, subjectDistance));
    float distanceVisibility = 1.0
        - (1.0 - cameraResolved) * (1.0 - subjectBoost);
    float sampledBroadVisibility = 1.0 - smoothstep(0.35, 1.20, pixelFootprint);
    float unresolvedWaveEnergy = saturate(max(
        stripeRisk * (1.0 - midField * 0.42),
        1.0 - sampledBroadVisibility
    ) * smoothstep(0.18, 0.92, normalizedViewRange));
    LandfallBoatFrame boat = landfallBoatFrame(p, ocean);
    LandfallWakeSample wake = landfallSampleWake(ocean, boat);
    LandfallHullSample hull = landfallSampleHullContact(in.height, ocean, boat);
    float rippleWarp = sin(dot(p, float2(0.173, -0.241)) - ocean.time * 0.31);
    float rippleA = dot(p, rippleDirectionA) * 1.42
        - ocean.time * 1.18 + rippleWarp * 0.28;
    float rippleB = dot(p, rippleDirectionB) * 2.05
        - ocean.time * 1.47 - rippleWarp * 0.36;
    float rippleC = dot(p, rippleDirectionC) * 3.55
        - ocean.time * 2.05 + rippleWarp * 0.52;
    // Wind arrives in short, uneven packets. Modulate the crossed ripple
    // slopes together so fine reflection breaks into calm and active patches
    // instead of exposing three uniform sinusoidal bands.
    float rippleGroup = smoothstep(
        0.18,
        0.86,
        0.5 + 0.5 * sin(
            dot(p, float2(-0.306, 0.952)) * 0.47
                - ocean.time * 0.24 + sin(rippleA - rippleB) * 0.32
        )
    );
    float rippleEnergy = mix(0.72, 1.16, rippleGroup);
    float2 capillarySlope = float2(0.0);
    float capillaryFacetRadiance = 0.0;
    float capillaryVisibility = 0.0;
    if (detailQuality > 0.75) {
        constexpr float2 capillaryDirectionA = float2(-0.952, 0.306);
        constexpr float2 capillaryDirectionB = float2(0.391, 0.920);
        float capillaryFootprint = max(
            max(
                abs(dot(footprintX, capillaryDirectionA)) * 8.4,
                abs(dot(footprintY, capillaryDirectionA)) * 8.4
            ),
            max(
                abs(dot(footprintX, capillaryDirectionB)) * 10.7,
                abs(dot(footprintY, capillaryDirectionB)) * 10.7
            )
        );
        capillaryVisibility = 1.0 - smoothstep(
            0.14,
            0.48,
            capillaryFootprint
        );
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
            capillaryDirectionA * (cos(rippleD) * 0.0065)
            + capillaryDirectionB * (cos(rippleE) * 0.0048)
        ) * capillaryVisibility * tierBlend
            * interference * nearRippleVisibility;
        float capillaryGroup = 0.5 + 0.5 * sin(
            dot(p, float2(0.673, -0.740)) * 1.17
                - ocean.time * 0.38 + sin(rippleD * 0.21) * 1.35
        );
        float groupEnvelope = mix(
            0.16,
            1.0,
            smoothstep(0.30, 0.78, capillaryGroup)
        );
        capillaryFacetRadiance = sin(rippleD) * sin(rippleE)
            * groupEnvelope * capillaryVisibility * tierBlend;
    }
    float2 detailSlope = (
        (
            rippleDirectionA * (cos(rippleA) * 0.026 * rippleVisibilityA)
            + rippleDirectionB * (cos(rippleB) * 0.025 * rippleVisibilityB)
            + rippleDirectionC * (cos(rippleC) * 0.016 * rippleVisibilityC)
        ) * rippleEnergy
        + capillarySlope
    ) * ocean.microNormalScale * mix(0.72, 1.14, nearField);
    detailSlope += wake.slope * macroVisibility * mix(0.76, 1.0, detailQuality);
    detailSlope += hull.slope * macroVisibility;
    float reflectionDetailGain = mix(0.90, 1.55, nearField);
    // Keep the real swell normal close to the camera, but suppress it where
    // grazing projection would turn a soft swell into a screen-wide band.
    float broadNormalVisibility = macroVisibility
        * distanceVisibility * sampledBroadVisibility
        * mix(0.22, 0.04, stripeRisk);
    float3 broadNormal = normalize(mix(
        float3(0.0, 1.0, 0.0),
        in.worldNormal,
        broadNormalVisibility
    ));
    float detailNormalVisibility = max(
        rippleVisibility * (1.0 - horizonField * 0.84),
        subjectBoost * 0.80
    ) * distanceVisibility * mix(0.65, 0.35, stripeRisk);
    float3 normal = normalize(mix(
        broadNormal,
        normalize(
            broadNormal
                + float3(-detailSlope.x, 0.0, detailSlope.y)
                    * reflectionDetailGain
        ),
        detailNormalVisibility
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

    // A grazing view travels through more water than a vertical one. Use that
    // optical path for absorption so oblique voyage views retain a deep body
    // beneath the reflected sky instead of flattening into one pale cyan wash.
    float opticalDepth = min(
        waterDepth / max(viewElevation, 0.22),
        24.0
    );
    float3 transmission = exp(-float3(0.155, 0.061, 0.027) * opticalDepth);
    float3 filteredWater = ocean.deepColor + (ocean.shallowColor - ocean.deepColor) * transmission;
    float3 body = mix(ocean.shallowColor, ocean.seaColor, smoothstep(0.35, 4.6, waterDepth));
    body = mix(body, ocean.deepColor, smoothstep(4.0, 20.0, waterDepth) * 0.82);
    float3 color = mix(body, filteredWater, 0.46);
    if (ocean.shoreline > 0.5) {
        float coastalLift = 1.0 - smoothstep(0.0, 11.0, max(shoreDistance, 0.0));
        color = mix(color, ocean.shallowColor, coastalLift * 0.22);
    }
    float underwaterScatter = exp(-opticalDepth * 0.16);
    color += ocean.shallowColor * underwaterScatter * 0.12;

    float detailColorGain = 0.28 * nearField
        * distanceVisibility * rippleVisibility;
    float2 shadedSlope = detailSlope * detailColorGain;
    float directionalShade = saturate(0.50 + dot(shadedSlope, float2(-3.2, 3.8)));
    color *= 0.96 + directionalShade * 0.08;

    float trough = 1.0 - smoothstep(-0.15, 0.005, in.height);
    float crest = smoothstep(0.045, 0.180, in.height);
    float elevationVisibility = broadNormalVisibility * 0.60;
    color = mix(color, ocean.deepColor, trough * 0.045 * elevationVisibility);
    color = mix(color, ocean.shallowColor, crest * 0.040 * elevationVisibility);

    float fresnel = 0.025 + 0.975 * pow(1.0 - saturate(dot(normal, viewDirection)), 5.0);
    float3 reflectionDirection = reflect(-viewDirection, normal);
    float3 celestialDirection = normalize(ocean.sunDirection);
    // At night the directional source is the moon. Preserve a small adapted
    // reflection response without lifting the diffuse water or whitewater.
    float lowLightAdaptation = 1.0 - smoothstep(
        0.18,
        0.48,
        ocean.sunStrength
    );
    float celestialReflectionStrength = mix(
        ocean.sunStrength,
        max(ocean.sunStrength, 0.34),
        lowLightAdaptation
    );
    float skyHeight = saturate(reflectionDirection.y * 0.72 + 0.36);
    float skyBlend = smoothstep(0.06, 0.90, skyHeight);
    // The zenith is optically deeper than the bright, humid horizon. Feeding
    // a little water-body color into that part of the environment gives each
    // real normal a different radiance to bend, instead of reflecting one cyan
    // wash regardless of its orientation.
    float zenithDepth = mix(0.16, 0.24, nearField);
    float3 zenithReflection = mix(
        ocean.skyColor * 1.04,
        ocean.deepColor,
        zenithDepth
    );
    float3 reflectedSky = mix(
        ocean.horizonColor * 1.035,
        zenithReflection,
        skyBlend
    );
    // Once individual slopes are smaller than a pixel, preserve their total
    // reflected energy as a broad rough-surface response. This removes visible
    // crest rows without flattening the far ocean into a uniform fog color.
    float3 integratedFarReflection = mix(
        ocean.horizonColor * 1.025,
        zenithReflection,
        0.14 + viewElevation * 0.18
    );
    reflectedSky = mix(
        reflectedSky,
        integratedFarReflection,
        unresolvedWaveEnergy * 0.78
    );
    float horizonHaze = 1.0 - smoothstep(0.02, 0.34, abs(reflectionDirection.y));
    reflectedSky = mix(reflectedSky, ocean.horizonColor * 1.06, horizonHaze * 0.28);
    // A broad celestial path connects the directional light to the horizon.
    // It complements the narrow specular aureole below without adding another
    // procedural pattern or fragment loop.
    float3 reflectedPlanar = reflectionDirection;
    reflectedPlanar.y = 0.0;
    float3 celestialPlanar = celestialDirection;
    celestialPlanar.y = 0.0;
    float azimuthAlignment = saturate(
        dot(reflectedPlanar, celestialPlanar) /
        max(length(reflectedPlanar) * length(celestialPlanar), 0.001)
    );
    float lowCelestial = 1.0 - smoothstep(
        0.28,
        0.72,
        abs(celestialDirection.y)
    );
    float celestialPath = horizonHaze
        * smoothstep(0.62, 0.96, azimuthAlignment)
        * mix(0.35, 1.0, lowCelestial);
    reflectedSky += ocean.sunColor
        * celestialReflectionStrength * celestialPath * 0.052;
    // The sun also brightens the air around it. Reflect that finite sky lobe
    // before the fine facet glints below: this creates a continuous light path
    // across broad waves, while the existing specular terms retain its broken
    // high-frequency core.
    float celestialAlignment = saturate(dot(reflectionDirection, celestialDirection));
    float celestialAureole = pow(
        celestialAlignment,
        mix(18.0, 12.0, lowLightAdaptation)
    ) * mix(0.06, 0.10, lowLightAdaptation)
        + pow(
            celestialAlignment,
            mix(96.0, 48.0, lowLightAdaptation)
        ) * mix(0.18, 0.22, lowLightAdaptation);
    reflectedSky += ocean.sunColor
        * (celestialReflectionStrength * celestialAureole);
    color = mix(color, reflectedSky, 0.04 + fresnel * 0.34);

    // Broad facets borrow sky color when they turn toward the light and expose
    // deeper water on the opposing face. The variation follows displaced waves,
    // so it cannot detach into a decorative surface pattern.
    float2 sunAcrossWater = float2(-celestialDirection.x, celestialDirection.z);
    sunAcrossWater /= max(length(sunAcrossWater), 0.001);
    float sunwardFacet = saturate(0.5 + dot(in.slope, sunAcrossWater) * 9.4);
    float facetLift = smoothstep(0.53, 0.74, sunwardFacet);
    float facetShade = 1.0 - smoothstep(0.27, 0.48, sunwardFacet);
    float facetVisibility = broadNormalVisibility
        * (1.0 - horizonField * 0.90);
    float3 facetSky = mix(ocean.horizonColor, ocean.skyColor, 0.32);
    color = mix(color, facetSky, facetLift * facetVisibility * 0.065);
    color = mix(color, ocean.deepColor, facetShade * facetVisibility * 0.045);

    // Preserve the fine normal field in color as well as in reflection.
    float microSlopeLength = length(detailSlope);
    float microFacetVisibility = rippleVisibility
        * nearField * nearField
        * (1.0 - horizonField * 0.96)
        * distanceVisibility
        * smoothstep(0.0015, 0.024, microSlopeLength);
    // Intersecting ripples form short facets, not full sinusoidal bands. Build
    // their radiance from the same normal phases so the light stays attached
    // to the moving surface while two directions break each other's stripes.
    float broadFacetRadiance = clamp(
        sin(rippleA) * sin(rippleB) * 0.72
            + sin(rippleB - rippleC) * 0.28,
        -1.0,
        1.0
    );
    float microFacetRadiance = mix(
        broadFacetRadiance,
        capillaryFacetRadiance,
        smoothstep(0.78, 1.0, detailQuality)
            * nearField * capillaryVisibility * 0.92
    );
    float microFacetContrast = mix(
        0.035,
        0.16,
        saturate(ocean.sunStrength)
    );
    color *= 1.0
        + microFacetRadiance * microFacetVisibility * microFacetContrast;
    float microFacetLift = saturate(microFacetRadiance)
        * microFacetVisibility;
    float microFacetShade = saturate(-microFacetRadiance)
        * microFacetVisibility;
    color = mix(
        color,
        facetSky,
        microFacetLift * mix(0.008, 0.020, saturate(ocean.sunStrength))
    );
    color = mix(color, ocean.deepColor, microFacetShade * 0.014);

    float3 halfVector = normalize(viewDirection + celestialDirection);
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
        * (1.0 - horizonField * 0.58)
        * distanceVisibility;
    color += ocean.sunColor * celestialReflectionStrength
        * (sunShoulder * glintBreakup * glintVisibility * 0.020
            + sunBroad * mix(0.18, 1.0, glintBreakup)
                * glintVisibility * 0.012
            + sunCore * glintBreakup * mix(0.28, 0.10, lowLightAdaptation));
    float crestSteepness = smoothstep(0.022, 0.052, length(in.slope));
    // A crest is a thin volume of water, not an opaque bright stripe. When the
    // sun sits behind it, Beer-Lambert transmission warms the upper, steep face
    // while the trough remains optically deep. Foam is composited afterwards,
    // so aerated fragments still replace the transmitted water where it breaks.
    float forwardScatter = pow(
        saturate(dot(viewDirection, -celestialDirection)),
        4.0
    );
    float daylightTransmission = smoothstep(0.18, 0.58, ocean.sunStrength);
    float thinCrest = crest * crestSteepness
        * macroVisibility * (1.0 - horizonField * 0.78)
        * distanceVisibility;
    float crestOpticalPath = mix(0.46, 0.18, crest);
    float3 crestTransmittance = exp(
        -float3(0.78, 0.28, 0.12) * crestOpticalPath
    );
    float3 transmittedCrest = mix(
        ocean.shallowColor,
        ocean.sunColor * crestTransmittance,
        0.46
    );
    float crestTransmission = thinCrest * forwardScatter
        * daylightTransmission * mix(0.16, 0.24, detailQuality);
    color = mix(color, transmittedCrest, saturate(crestTransmission));

    float foamWarp = sin(
        dot(p, float2(-1.37, 2.11)) - ocean.time * 0.33
    );
    float foamA = sin(
        dot(p, float2(4.73, 3.11)) - ocean.time * 1.07 + foamWarp * 1.20
    );
    float foamB = sin(
        dot(p, float2(-6.29, 2.57)) + ocean.time * 0.79 - foamA * 0.55
    );
    float foamC = sin(
        dot(p, float2(2.17, -8.41)) - ocean.time * 1.31 + foamB * 0.43
    );
    float foamTurbulence = saturate(
        0.50 + foamA * 0.23 + foamB * 0.17 + foamC * 0.10
    );
    float foamFilter = max(fwidth(foamTurbulence) * 0.62, 0.015);
    float foamFragments = smoothstep(
        0.72 - foamFilter,
        0.88 + foamFilter,
        foamTurbulence
    );
    float crestRangeVisibility = 1.0 - smoothstep(
        0.38,
        0.68,
        normalizedViewRange
    );
    float crestFoam = in.breaking * mix(0.46, 1.0, crestSteepness) * foamFragments
        * macroVisibility * crestRangeVisibility;
    float decayTexture = 0.5 + 0.5 * sin(
        dot(p, float2(-2.17, 3.83)) - ocean.time * 0.41 + foamWarp * 1.10
    );
    float decayFilter = max(fwidth(decayTexture) * 0.55, 0.015);
    float decayFragments = foamFragments * mix(
        0.12,
        0.48,
        smoothstep(0.42 - decayFilter, 0.80 + decayFilter, decayTexture)
    );
    float remnantFoam = in.foamRemnant
        * mix(0.04, 0.16, crestSteepness)
        * decayFragments * macroVisibility * (1.0 - horizonField * 0.84);
    // Foam scatters the light available in the scene; it does not glow with a
    // fixed white value after sunset. Keep the same material response at every
    // time of day while letting the shared lighting palette set its radiance.
    float foamIllumination = saturate(0.34 + ocean.sunStrength * 0.50);
    float3 foamColor = mix(
        ocean.shallowColor,
        ocean.lightColor,
        foamIllumination
    );
    float foamCoverage = 1.0 - exp2(
        -(crestFoam * 0.70 + remnantFoam * 0.08)
    );
    color = mix(
        color,
        foamColor,
        saturate(foamCoverage)
    );

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
        color = mix(color, foamColor, shoreFoam * 0.76);
    }

    if (ocean.boatPresence > 0.5) {
        color = mix(color, ocean.deepColor, hull.submergedShadow * 0.24);
        float2 viewAcrossWater = float2(viewDirection.x, -viewDirection.z);
        viewAcrossWater /= max(length(viewAcrossWater), 0.001);
        float2 fromBoat = boat.heading * boat.longitudinal
            + boat.across * boat.lateral;
        // Project the real waterplane onto the camera-facing surface, then let
        // the same wave normal bend and break the reflected silhouette. This
        // keeps the reflection attached without drawing a mirrored boat decal.
        float2 reflectionAcrossAxis = float2(
            -viewAcrossWater.y,
            viewAcrossWater.x
        );
        float projectedHalfDepth =
            abs(dot(boat.heading, viewAcrossWater)) * boat.halfLength
            + abs(dot(boat.across, viewAcrossWater)) * boat.halfBeam;
        float projectedHalfSpan =
            abs(dot(boat.heading, reflectionAcrossAxis)) * boat.halfLength
            + abs(dot(boat.across, reflectionAcrossAxis)) * boat.halfBeam;
        float reflectionDistance = dot(fromBoat, viewAcrossWater)
            - projectedHalfDepth;
        float reflectionLength = max(boat.halfLength * 0.92, 0.72)
            * mix(0.80, 1.65, 1.0 - viewElevation);
        float waveShift = dot(detailSlope, viewAcrossWater) * 1.8;
        float reflectionAge = saturate(
            (reflectionDistance + waveShift) / reflectionLength
        );
        float reflectionSpan = projectedHalfSpan
            * mix(0.96, 0.44, reflectionAge);
        float acrossDistance = abs(
            dot(fromBoat, reflectionAcrossAxis)
                + dot(detailSlope, reflectionAcrossAxis) * 2.6
        );
        float projectedReflection = smoothstep(
            -0.045,
            0.080,
            reflectionDistance + waveShift
        ) * (1.0 - smoothstep(0.68, 1.0, reflectionAge))
            * (1.0 - smoothstep(
                reflectionSpan * 0.66,
                reflectionSpan,
                acrossDistance
            ));
        float projectedBreakup = smoothstep(
            0.24,
            0.82,
            0.5 + 0.5 * sin(
                reflectionDistance * 8.3
                    + dot(p, reflectionAcrossAxis) * 5.1
                    + in.height * 17.0 - ocean.time * 0.46
            )
        );
        projectedReflection *= mix(0.42, 1.0, projectedBreakup)
            * macroVisibility;
        float reflectionFacing = smoothstep(
            -0.20,
            0.72,
            dot(fromBoat / max(length(fromBoat), 0.001), viewAcrossWater)
        );
        // A hull reflection falls onto the camera-facing water instead of
        // surrounding the boat as an even halo. Water absorption and the
        // current light level tint that lobe before wave breakup is applied.
        float reflectionLobe = mix(0.08, 1.0, reflectionFacing);
        float reflectionIllumination = saturate(
            0.24 + ocean.sunStrength * 0.48
        );
        float3 reflectedHullColor = mix(
            ocean.deepColor,
            ocean.boatReflectionColor,
            reflectionIllumination
        );
        float reflectionWeight = hull.reflectedHull * reflectionLobe
                * (0.025 + hull.reflectionBreakup * 0.095)
            + projectedReflection
                * (0.028 + projectedBreakup * 0.080)
                * mix(0.76, 1.12, fresnel);
        color = mix(
            color,
            reflectedHullColor,
            saturate(reflectionWeight)
        );
        float meniscusFacing = mix(0.22, 1.0, reflectionFacing);
        color = mix(
            color,
            foamColor,
            hull.meniscusLight * meniscusFacing * 0.11
        );
        color = mix(color, ocean.shallowColor, hull.bowDisturbance * 0.065);
        color = mix(color, foamColor, hull.bowAeration * 0.22);

        // The same dusk factor that raises the physical deck lantern also
        // creates a restrained pair of stern-quarter reflections. Two soft
        // lobes cover both single-lantern and twin-lamp ships without encoding
        // model-specific positions in the ocean renderer.
        float lanternVisibility = 1.0 - smoothstep(0.10, 0.72, ocean.sunStrength);
        float lanternLongitudinal = boat.longitudinal + boat.halfLength * 0.82;
        float lanternQuarter = boat.halfBeam * 0.58;
        float portLanternDistance = length(float2(
            lanternLongitudinal,
            boat.lateral - lanternQuarter
        ));
        float starboardLanternDistance = length(float2(
            lanternLongitudinal,
            boat.lateral + lanternQuarter
        ));
        float lanternDistance = min(portLanternDistance, starboardLanternDistance);
        float lanternRadius = max(boat.halfBeam * 1.8, 0.34);
        float lanternPool = exp(-pow(lanternDistance / lanternRadius, 2.0))
            * lanternVisibility * macroVisibility;
        float3 lanternColor = mix(
            ocean.lightColor,
            float3(1.0, 0.24, 0.04),
            0.55
        );
        color += lanternColor * lanternPool * (0.012 + fresnel * 0.024);
    }

    if (wake.disturbance > 0.0) {
        // Disturbed water scatters a small amount of horizon radiance before the
        // most aerated pockets become foam. Both use the wake sample that already
        // perturbed the normal above, so this reads as rough water instead of a
        // white V decal and remains legible at the 17 Pro Max voyage distance.
        float3 wakeScatterColor = mix(
            ocean.shallowColor,
            ocean.horizonColor,
            0.38 + fresnel * 0.22
        );
        float wakeScatter = wake.disturbance * (0.045 + fresnel * 0.055);
        color = mix(color, wakeScatterColor, wakeScatter);
        color = mix(color, foamColor, wake.aeration * 0.26);
    }

    // Aerial perspective must finish at the same radiance as the sky behind
    // the finite mesh. Leaving even a small amount of body color at the final
    // row exposes the plane as a straight horizontal cut.
    // Begin before perspective compresses the last mesh rows into one pixel.
    // The transition then spans several distant wave bands instead of becoming
    // a single ruler-straight color step at the geometric edge.
    float atmosphereEnd = clamp(
        min(ocean.surfaceSize.x, ocean.surfaceSize.y) * 0.55,
        46.0,
        54.0
    );
    float farAtmosphere = smoothstep(
        atmosphereEnd * 0.56,
        atmosphereEnd,
        cameraDistance
    );
    float edgeAtmosphere = max(
        smoothstep(
            ocean.surfaceSize.x * 0.43,
            ocean.surfaceSize.x * 0.50,
            abs(in.localPosition.x)
        ),
        smoothstep(
            ocean.surfaceSize.y * 0.43,
            ocean.surfaceSize.y * 0.50,
            abs(in.localPosition.y)
        )
    );
    farAtmosphere = max(farAtmosphere, edgeAtmosphere);
    float samplingHaze = max(
        (1.0 - sampledBroadVisibility) * 0.08,
        unresolvedWaveEnergy * 0.06
    );
    float atmosphericHaze = farAtmosphere
        + (1.0 - farAtmosphere) * samplingHaze;
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
