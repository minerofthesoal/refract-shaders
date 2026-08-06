#version 120
/* Refract Shaders - world1/composite.fsh (End dimension override)

   Iris/OptiFine loads this instead of the root shaders/composite.fsh
   whenever the player is in the End (world1 = End, world-1 = Nether -
   see dimension_properties in the Iris docs). Anything not overridden
   here (gbuffers_terrain, gbuffers_water, composite1/2 bloom, final.fsh)
   is inherited from the root shaders/ folder, and already reads
   End-correct ambient/horizon/sun colors via the CAT_THE_END branches
   added to lib/common.glsl's getAmbientSkyColor/getHorizonSkyColor/
   getSunColor.

   Dropped vs. the overworld composite.fsh:
     - raymarched clouds - vanilla never spawns clouds in the End, and
       the open sky above the main island would otherwise render
       fluffy white overworld clouds straight over the void, which is
       a clearly wrong sky for this dimension
     - wet-reflection puddles - no rain/wetness in the End
     - the overworld's sun-glare disc - there's no visible sun to draw
       a glare around

   Kept, re-tinted: SSAO (purely geometric), the SSRT contact-shadow
   pass, and a volumetric light-shaft effect. The End is one of the few
   places shadowLightPosition is actually a fixed, non-cycling
   direction (no day/night in the End), so unlike the Nether (where
   skyLight is ~0 and this would never be visible anyway) a raymarched
   shaft here reads as a stable, moody beam through the void rather
   than god-rays chasing a moving sun - a look several other Iris packs
   lean into for End Cities/obsidian pillars, so it's kept here instead
   of stripped like the Nether's.

   New: a constant (not day/night-gated) violet void-mist ground haze
   in place of the overworld's night-only atmospheric fog. */

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

// Fixed-angle volumetric light shaft. Structurally the same raymarch as
// the overworld's computeGodRays, but there's no rainFade term (no
// weather in the End) and the color comes from getSunColor()'s
// CAT_THE_END branch (a fixed pale violet) instead of the overworld's
// day/night sun color.
vec3 computeVoidShaft(vec3 worldDirToFrag, float maxDist) {
    if (GODRAY_STRENGTH <= 0.0) return vec3(0.0);

    vec3 rayDir = normalize(worldDirToFrag);
    float marchDist = min(maxDist, SHADOW_DISTANCE * 0.9);

    int steps = GODRAY_STEPS;
    float stepSize = marchDist / float(steps);

    vec2 fc = gl_FragCoord.xy + frameTimeCounter * 13.7;
    float dither = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
    vec3 samplePos = rayDir * stepSize * dither;

    float accum = 0.0;
    for (int i = 0; i < steps; i++) {
        vec3 shadowClip = worldToShadowClip(samplePos);
        accum += sampleShadowPCF(shadowtex1, shadowClip);
        samplePos += rayDir * stepSize;
    }
    accum /= float(steps);

    vec3 lightDir = normalize(shadowLightPosition);
    float cosTheta = dot(rayDir, lightDir);
    float scattering = phaseHG(cosTheta, 0.82) * 4.0 * PI;

    return accum * scattering * getSunColor() * GODRAY_STRENGTH * 0.05;
}

// ---------------------------------------------------------------------
// Void mist - constant (not day/night-gated) low violet-black ground
// haze, replacing the overworld's night-only atmospheric fog.
// ---------------------------------------------------------------------
vec3 applyVoidMist(vec3 color, vec3 worldPos, float dist, bool isSky) {
    if (isSky || NIGHT_FOG_STRENGTH <= 0.0) return color;

    vec3 absoluteWorld = mod(worldPos + cameraPosition, 10000.0);
    float drift = frameTimeCounter * 0.01;
    float mistNoise = cloudFBM(vec3(absoluteWorld.xz * 0.015 + drift, drift * 0.4));

    float density = (1.0 - exp(-dist * 0.010)) * mix(0.5, 1.0, mistNoise);
    float heightFalloff = exp(-max(worldPos.y + 2.0, 0.0) * 0.035);
    density *= heightFalloff * NIGHT_FOG_STRENGTH;
    density = clamp(density, 0.0, 0.5);
    if (density < 0.005) return color;

    vec3 mistTint = mix(vec3(0.035, 0.020, 0.055), vec3(0.06, 0.045, 0.09), mistNoise);
    return mix(color, mistTint, density);
}

void main() {
    vec4 sceneColor = texture2D(colortex0, texcoord);
    float depth = texture2D(depthtex0, texcoord).r;
    vec4 normalSample = texture2D(colortex1, texcoord);
    vec3 viewNormal = normalize(normalSample.rgb * 2.0 - 1.0);

    vec3 worldPos = reconstructWorldPos(texcoord, depth);
    vec3 viewPos = reconstructViewPos(texcoord, depth);
    float dist = length(worldPos);

    vec3 color = sceneColor.rgb;

#if SSAO == 1
    if (depth < 0.9999) {
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
    float marchDist = isSky ? SHADOW_DISTANCE * 0.9 : dist;

    color += computeVoidShaft(worldPos, marchDist);
    color = applyVoidMist(color, worldPos, dist, isSky);

    // Distance haze toward the End-tuned horizon tone (see
    // getHorizonSkyColor's CAT_THE_END branch in lib/common.glsl).
    float hazeAmount = clamp(dist / (SHADOW_DISTANCE * 2.2), 0.0, 1.0) * 0.16;
    color = mix(color, getHorizonSkyColor(), hazeAmount * (1.0 - float(isSky)));

    gl_FragData[0] = vec4(color, sceneColor.a);
}
