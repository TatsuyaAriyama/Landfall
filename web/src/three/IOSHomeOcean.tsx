import { useEffect, useMemo } from "react";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";

// HomeIslandOceanEffects.Layout.voyageHome と同じ寸法・分割数。
const OCEAN_WIDTH = 240;
const OCEAN_DEPTH = 170;
const OCEAN_CENTER_X = 24;

const OCEAN_VERTEX = /* glsl */ `
  precision highp float;
  uniform float uTime;
  uniform vec2 uSurfaceSize;
  uniform vec2 uCoordinateOffset;
  varying vec2 vLocalP;

  #include <fog_pars_vertex>

  void main() {
    vec2 localP = position.xy;
    vec2 p = localP + uCoordinateOffset;
    float distanceFromIsland = length(vec2(p.x * 0.72, p.y));
    float calm = mix(0.42, 1.0, smoothstep(11.0, 34.0, distanceFromIsland));
    float warpPhase = p.x * 0.058 + p.y * 0.081 - uTime * 0.23;
    float warp = sin(warpPhase) * 1.05;
    vec2 q = p + vec2(warp, -warp * 0.48);
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
    vec3 transformed = position;
    transformed.z += height * edgeX * edgeY;
    vLocalP = localP;
    vec4 mvPosition = modelViewMatrix * vec4(transformed, 1.0);
    gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
  }
`;

const OCEAN_FRAGMENT = /* glsl */ `
  precision highp float;
  uniform float uTime;
  uniform vec3 uShallow;
  uniform vec3 uSea;
  uniform vec3 uDeep;
  uniform vec3 uLight;
  uniform vec3 uFogColor;
  uniform vec2 uCoordinateOffset;
  varying vec2 vLocalP;

  #include <fog_pars_fragment>

  void main() {
    vec2 p = vLocalP + uCoordinateOffset;
    float distanceFromIsland = length(vec2(p.x * 0.72, p.y));
    float calm = mix(0.42, 1.0, smoothstep(11.0, 34.0, distanceFromIsland));
    float warpPhase = p.x * 0.058 + p.y * 0.081 - uTime * 0.23;
    float warp = sin(warpPhase) * 1.05;
    vec2 q = p + vec2(warp, -warp * 0.48);
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
    vec2 slope = vec2(
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
    vec3 col = mix(uShallow, uSea, shallowMix);
    col = mix(col, uDeep, deepMix * 0.72);
    float directionalShade = clamp(0.52 + slope.x * 3.6 + slope.y * 3.1, 0.0, 1.0);
    col *= 0.975 + directionalShade * 0.07;

    float trough = 1.0 - smoothstep(-0.13, 0.008, height);
    float crest = smoothstep(0.035, 0.155, height);
    col = mix(col, uDeep, trough * 0.055);
    col = mix(col, uLight, crest * 0.16);

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
    col = mix(col, uFogColor, horizon * 0.24);
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
    #include <fog_fragment>
  }
`;

export default function IOSHomeOcean({ animate }: { animate: boolean }) {
  const material = useMemo(
    () =>
      new THREE.ShaderMaterial({
        name: "landfall-ios-home-ocean",
        vertexShader: OCEAN_VERTEX,
        fragmentShader: OCEAN_FRAGMENT,
        fog: true,
        side: THREE.DoubleSide,
        uniforms: {
          ...THREE.UniformsUtils.clone(THREE.UniformsLib.fog),
          uTime: { value: 0 },
          uShallow: { value: new THREE.Color("#22DDBD") },
          uSea: { value: new THREE.Color("#18B9C9") },
          uDeep: { value: new THREE.Color("#087895") },
          uLight: { value: new THREE.Color("#EFFFF7") },
          uFogColor: { value: new THREE.Color("#93D9D3") },
          uSurfaceSize: { value: new THREE.Vector2(OCEAN_WIDTH, OCEAN_DEPTH) },
          uCoordinateOffset: { value: new THREE.Vector2(OCEAN_CENTER_X, 0) },
        },
      }),
    [],
  );
  const geometry = useMemo(
    () => new THREE.PlaneGeometry(OCEAN_WIDTH, OCEAN_DEPTH, 144, 96),
    [],
  );

  useEffect(
    () => () => {
      material.dispose();
      geometry.dispose();
    },
    [geometry, material],
  );

  useFrame(({ clock }) => {
    if (animate) material.uniforms.uTime.value = clock.elapsedTime;
  });

  return (
    <group>
      <mesh
        geometry={geometry}
        material={material}
        position={[OCEAN_CENTER_X, 0, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
        frustumCulled={false}
      />
      <mesh position={[OCEAN_CENTER_X, -0.5, 0]} rotation={[-Math.PI / 2, 0, 0]}>
        <planeGeometry args={[OCEAN_WIDTH, OCEAN_DEPTH]} />
        <meshBasicMaterial color="#28A7B7" side={THREE.DoubleSide} />
      </mesh>
    </group>
  );
}
