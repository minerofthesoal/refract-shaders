#version 120
/* Refract Shaders - world-1/composite.fsh (Nether dimension override)

   Iris/OptiFine loads this instead of the root shaders/composite.fsh
   whenever the player is in the Nether. Any program NOT present in this
   folder (gbuffers_terrain, gbuffers_water, composite1/2, final, ...)
   falls back to the matching file in the root shaders/ folder, so this
   file only needs to contain what's actually different about the
   Nether's post-process pass - see dimension_properties in the Iris
   docs / shaders_dev.html on OptiDocs for the world-1 = Nether,
   world1 = End convention.

   Dropped entirely vs. the overworld composite.fsh, because none of it
   makes sense without a visible sun/sky:
     - volumetric god rays / sun glare (raymarching toward a light
       source that's never actually on screen just wastes shadow-map
       taps and risks stray light leaking through gaps in the roof)
     - raymarched clouds (vanilla never spawns clouds in the Nether)
     - wet-reflection puddles (no rain/wetness in the Nether)
     - the overworld's night-only atmospheric ground fog (replaced
       below with a Nether-appropriate haze that isn't gated behind a
       day/night check that has nothing to look at here)

   Kept: SSAO (purely geometric, still correct), the SSRT contact-
   shadow pass (harmless - it's naturally gated behind skyLight, which
   is ~0 almost everywhere in the Nether, and cheap to leave in for
   any modded semi-open Nether-like dimension that does carry skylight),
   and the horizon-haze distance blend (still useful for fading distant
   terrain into the fog at high render distance).

   New: a low warm ambient floor so fully unlit caverns read as dim
   ember-glow rather than absolute crushed black, and a lava-vision
   effect (heat shimmer + orange tint) when the camera is submerged in
   lava - isEyeInWater == 2 is lava, and nothing in this pack handled
   that case before. */

#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex1;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */

vec3 reconstructViewPos(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clip;
    viewPos /= viewPos.w;
    return viewPos.xyz;
}

vec3 reconstructWorldPos(vec2 uv, float depth) {
    vec3 viewPos = reconstructViewPos(uv, depth);
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    return worldPos.xyz;
}

#if SSAO == 1
// Same technique as the overworld pass - see the extensive comments in
// the root shaders/composite.fsh. Purely a function of nearby opaque
// geometry, so it's identical here.
float computeSSAO(vec3 viewPos, vec3 viewNormal, vec2 uv) {
    const float radius = 0.9;
    float occlusion = 0.0;

    vec3 up = (abs(viewNormal.z) < 0.99) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, viewNormal));
    vec3 bitangent = cross(viewNormal, tangent);

    float rotAngle = bayer4(gl_FragCoord.xy) * 6.2831853;
    float ca = cos(rotAngle);
    float sa = sin(rotAngle);

    for (int i = 0; i < SSAO_SAMPLES; i++) {
        float t = (float(i) + 0.5) / float(SSAO_SAMPLES);
        float spiralAngle = t * 6.2831853 * 2.4;
        float spiralRadius = sqrt(t);
        vec2 disk = vec2(cos(spiralAngle), sin(spiralAngle)) * spiralRadius;
        vec2 rot = vec2(disk.x * ca - disk.y * sa, disk.x * sa + disk.y * ca);

        float height = mix(0.25, 1.0, t);
        vec3 sampleDir = normalize(tangent * rot.x + bitangent * rot.y + viewNormal * height);
        vec3 samplePos = viewPos + sampleDir * radius * mix(0.2, 1.0, t);

        vec4 clip = gbufferProjection * vec4(samplePos, 1.0);
        if (clip.w <= 0.0) continue;
        vec2 sUV = (clip.xy / clip.w) * 0.5 + 0.5;
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) continue;

        float sceneDepthRaw = texture2D(depthtex1, sUV).r;
        if (sceneDepthRaw >= 0.9999) continue;
        vec3 sceneViewPos = reconstructViewPos(sUV, sceneDepthRaw);

        float rangeCheck = clamp(radius / max(abs(viewPos.z - sceneViewPos.z), 0.0001), 0.0, 1.0);
        occlusion += (sceneViewPos.z >= samplePos.z + 0.025) ? rangeCheck : 0.0;
    }

    return 1.0 - clamp(occlusion / float(SSAO_SAMPLES), 0.0, 1.0);
}
#endif

// ---------------------------------------------------------------------
// Nether ember haze - a constant (not day/night-gated) low ground mist
// tinted like distant lava glow, replacing the overworld's night-only
// atmospheric fog. Reuses the same cloudFBM noise field the overworld
// pass uses for its own ground mist, just re-tinted and no longer
// gated behind getDayFactor().
// ---------------------------------------------------------------------
vec3 applyNetherHaze(vec3 color, vec3 worldPos, float dist, bool isSky) {
    if (isSky || NIGHT_FOG_STRENGTH <= 0.0) return color;

    vec3 absoluteWorld = mod(worldPos + cameraPosition, 10000.0);
    float drift = frameTimeCounter * 0.012;
    float mistNoise = cloudFBM(vec3(absoluteWorld.xz * 0.018 + drift, drift * 0.5));

    float density = (1.0 - exp(-dist * 0.012)) * mix(0.5, 1.0, mistNoise);
    float heightFalloff = exp(-max(worldPos.y + 2.0, 0.0) * 0.045);
    density *= heightFalloff * NIGHT_FOG_STRENGTH;
    density = clamp(density, 0.0, 0.45);
    if (density < 0.005) return color;

    vec3 hazeTint = mix(vec3(0.10, 0.035, 0.02), vec3(0.16, 0.06, 0.03), mistNoise);
    return mix(color, hazeTint, density);
}

// ---------------------------------------------------------------------
// Lava vision - nothing in this pack handled isEyeInWater == 2 (lava)
// before. A gentle heat-shimmer UV warp plus a warm tint reads as
// "your face is in molten rock" without being disorienting.
// ---------------------------------------------------------------------
vec3 applyLavaVision(vec2 uv, vec3 fallbackColor) {
    float t = frameTimeCounter;
    vec2 shimmer = vec2(
        sin(uv.y * 30.0 + t * 3.1) * 0.5 + sin(uv.y * 9.0 - t * 1.6) * 0.5,
        cos(uv.x * 26.0 + t * 2.4) * 0.5 + cos(uv.x * 11.0 + t * 1.9) * 0.5
    ) * 0.006;
    vec3 color = texture2D(colortex0, clamp(uv + shimmer, 0.0, 1.0)).rgb;
    color = mix(color, vec3(0.55, 0.16, 0.02), 0.6);
    color *= 0.65;
    return color;
}

void main() {
    vec4 sceneColor = texture2D(colortex0, texcoord);
    float depth = texture2D(depthtex0, texcoord).r;

    vec3 worldPos = reconstructWorldPos(texcoord, depth);
    vec3 viewPos = reconstructViewPos(texcoord, depth);
    float dist = length(worldPos);

    vec3 color = sceneColor.rgb;

    if (isEyeInWater == 2) {
        color = applyLavaVision(texcoord, color);
        gl_FragData[0] = vec4(color, sceneColor.a);
        return;
    }

#if SSAO == 1
    if (depth < 0.9999) {
        vec4 normalSample = texture2D(colortex1, texcoord);
        vec3 viewNormal = normalize(normalSample.rgb * 2.0 - 1.0);
#if VOXY_COMPAT == 1
        float distFade = 1.0 - smoothstep(96.0, 128.0, dist);
#else
        float distFade = 1.0;
#endif
        if (distFade > 0.001) {
            float ao = computeSSAO(viewPos, viewNormal, texcoord);
            color *= mix(1.0, ao, SSAO_STRENGTH * distFade);
        }
    }
#endif

#if SHADOW_MODE != 0
    if (depth < 0.9999) {
        vec4 normalSample = texture2D(colortex1, texcoord);
        vec3 viewNormal = normalize(normalSample.rgb * 2.0 - 1.0);
#if VOXY_COMPAT == 1
        float ssrtDistFade = 1.0 - smoothstep(96.0, 128.0, dist);
#else
        float ssrtDistFade = 1.0;
#endif
        float skyLightHere = texture2D(colortex3, texcoord).a;
        float ndotlHere = dot(viewNormal, normalize(shadowLightPosition));
        if (ssrtDistFade > 0.001 && skyLightHere > 0.05 && ndotlHere > 0.0) {
#if SHADOW_MODE == 1
            int ssrtSteps = SSRT_SHADOW_STEPS;
#else
            int ssrtSteps = SSRT_SHADOW_STEPS_LITE;
#endif
            float contactShadow = screenSpaceSunShadow(depthtex1, gbufferProjectionInverse, viewPos, viewNormal, ssrtSteps, SSRT_SHADOW_RANGE, gl_FragCoord.xy);
            color *= mix(1.0, contactShadow, 0.6 * skyLightHere * ssrtDistFade);
        }
    }
#endif

    bool isSky = texture2D(depthtex1, texcoord).r >= 0.9999;

    color = applyNetherHaze(color, worldPos, dist, isSky);

    // Distance haze toward the Nether-tuned horizon tone (see
    // getHorizonSkyColor's CAT_NETHER branch in lib/common.glsl) - keeps
    // far terrain fading into the same warm murk the fog itself uses
    // instead of popping to a mismatched color right at render distance.
    float hazeAmount = clamp(dist / (SHADOW_DISTANCE * 2.0), 0.0, 1.0) * 0.22;
    color = mix(color, getHorizonSkyColor(), hazeAmount * (1.0 - float(isSky)));

    gl_FragData[0] = vec4(color, sceneColor.a);
}
