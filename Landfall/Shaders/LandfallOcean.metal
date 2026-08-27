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
    float4x4 normalTransform;
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
};

struct LandfallOceanVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 localPosition;
    float2 oceanPosition;
    float2 slope;
    float height;
};

struct LandfallWaveSample {
    float height;
    float2 slope;
    float2 horizontal;
};

static inline LandfallWaveSample landfallSampleWaves(float2 p, float time) {
    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float calm = mix(0.36, 1.0, smoothstep(10.0, 34.0, distanceFromIsland));

    constexpr float2 dirA = float2(0.342, 0.940);
    constexpr float2 dirB = float2(-0.766, 0.643);
    constexpr float2 dirC = float2(0.906, 0.423);
    constexpr float2 dirD = float2(-0.259, 0.966);
    constexpr float2 dirE = float2(0.643, -0.766);
    float phaseA = dot(p, dirA) * 0.105 - time * 0.42;
    float phaseB = dot(p, dirB) * 0.155 - time * 0.36 + 1.70;
    float phaseC = dot(p, dirC) * 0.340 - time * 0.78 + 0.45;
    float phaseD = dot(p, dirD) * 0.720 - time * 1.22 + 2.10;
    float phaseE = dot(p, dirE) * 1.250 - time * 1.68 + 0.90;

    float height = (
        sin(phaseA) * 0.150
        + sin(phaseB) * 0.090
        + sin(phaseC) * 0.035
        + sin(phaseD) * 0.014
        + sin(phaseE) * 0.005
    ) * calm;
    float2 slope = (
        dirA * (cos(phaseA) * 0.150 * 0.105)
        + dirB * (cos(phaseB) * 0.090 * 0.155)
        + dirC * (cos(phaseC) * 0.035 * 0.340)
        + dirD * (cos(phaseD) * 0.014 * 0.720)
        + dirE * (cos(phaseE) * 0.005 * 1.250)
    ) * calm;
    float2 horizontal = (
        dirA * (cos(phaseA) * 0.150 * 0.62)
        + dirB * (cos(phaseB) * 0.090 * 0.54)
        + dirC * (cos(phaseC) * 0.035 * 0.38)
    ) * calm;
    return {height, slope, horizontal};
}

vertex LandfallOceanVertexOut landfallOceanVertex(
    LandfallOceanVertexIn in [[stage_in]],
    constant SCNSceneBuffer& frame [[buffer(0)]],
    constant LandfallOceanNodeBuffer& node [[buffer(1)]],
    constant LandfallOceanUniforms& ocean [[buffer(2)]])
{
    float2 localPosition = in.position.xy;
    float2 oceanPosition = localPosition + ocean.coordinateOffset;
    LandfallWaveSample waves = landfallSampleWaves(oceanPosition, ocean.time);

    float edgeX = 1.0 - smoothstep(
        ocean.surfaceSize.x * 0.43,
        ocean.surfaceSize.x * 0.50,
        abs(localPosition.x)
    );
    float edgeY = 1.0 - smoothstep(
        ocean.surfaceSize.y * 0.43,
        ocean.surfaceSize.y * 0.50,
        abs(localPosition.y)
    );
    float edge = edgeX * edgeY;
    float3 displaced = in.position;
    displaced.xy += waves.horizontal * edge;
    displaced.z += waves.height * edge;
    float3 localNormal = normalize(float3(-waves.slope * edge, 1.0));

    LandfallOceanVertexOut out;
    out.position = node.modelViewProjectionTransform * float4(displaced, 1.0);
    out.worldPosition = (node.modelTransform * float4(displaced, 1.0)).xyz;
    out.worldNormal = normalize((node.normalTransform * float4(localNormal, 0.0)).xyz);
    out.localPosition = localPosition;
    out.oceanPosition = oceanPosition;
    out.slope = waves.slope * edge;
    out.height = waves.height * edge;
    return out;
}

fragment half4 landfallOceanFragment(
    LandfallOceanVertexOut in [[stage_in]],
    constant SCNSceneBuffer& frame [[buffer(0)]],
    constant LandfallOceanUniforms& ocean [[buffer(2)]])
{
    float2 p = in.oceanPosition;
    float rippleA = dot(p, float2(0.829, 0.559)) * 1.82 - ocean.time * 1.18;
    float rippleB = dot(p, float2(-0.616, 0.788)) * 2.66 - ocean.time * 1.47;
    float rippleC = dot(p, float2(0.225, 0.974)) * 4.85 - ocean.time * 2.05;
    float2 detailSlope = (
        float2(0.829, 0.559) * (cos(rippleA) * 0.032)
        + float2(-0.616, 0.788) * (cos(rippleB) * 0.023)
        + float2(0.225, 0.974) * (cos(rippleC) * 0.010)
    ) * ocean.microNormalScale;
    float3 normal = normalize(in.worldNormal + float3(-detailSlope.x, 0.0, detailSlope.y));

    float distanceFromIsland = length(float2(p.x * 0.72, p.y));
    float waterDepth = 5.0 + smoothstep(0.0, 90.0, distanceFromIsland) * 13.0;
    float3 transmission = exp(-float3(0.155, 0.061, 0.027) * min(waterDepth, 24.0));
    float3 filteredWater = ocean.deepColor + (ocean.shallowColor - ocean.deepColor) * transmission;
    float3 body = mix(ocean.shallowColor, ocean.seaColor, smoothstep(0.35, 4.6, waterDepth));
    body = mix(body, ocean.deepColor, smoothstep(4.0, 20.0, waterDepth) * 0.82);
    float3 color = mix(body, filteredWater, 0.46);

    float3 cameraPosition = frame.inverseViewTransform[3].xyz;
    float3 viewDirection = normalize(cameraPosition - in.worldPosition);
    float fresnel = 0.025 + 0.975 * pow(1.0 - saturate(dot(normal, viewDirection)), 5.0);
    float3 reflectionDirection = reflect(-viewDirection, normal);
    float skyHeight = saturate(reflectionDirection.y * 0.72 + 0.36);
    float3 reflectedSky = mix(ocean.horizonColor, ocean.skyColor, smoothstep(0.08, 0.88, skyHeight));
    color = mix(color, reflectedSky, 0.085 + fresnel * 0.60);

    float3 halfVector = normalize(viewDirection + normalize(ocean.sunDirection));
    float sunFacing = max(dot(normal, halfVector), 0.0);
    float sunBroad = pow(sunFacing, 48.0);
    float sunCore = pow(sunFacing, 192.0);
    color += ocean.sunColor * ocean.sunStrength * (sunBroad * 0.015 + sunCore * 0.18);

    float crest = smoothstep(0.045, 0.180, in.height);
    float crestSteepness = smoothstep(0.028, 0.058, length(in.slope));
    color = mix(color, float3(0.92, 0.99, 0.97), crest * crestSteepness * 0.38);
    return half4(half3(saturate(color)), 1.0h);
}
