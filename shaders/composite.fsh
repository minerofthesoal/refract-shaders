#version 120
/* Refract Shaders - composite.fsh
   First post-processing pass: reconstructs world position from depth,
   raymarches toward the sun/moon through the shadow map to produce
   volumetric god rays, and blends additional atmospheric depth fog. */

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
// Screen-space ambient occlusion: darkens creases, corners, and contact
// points between objects - the areas where ambient sky light realistically
// struggles to bounce in, which a single directional shadow map has no
// way to represent on its own (it only knows about occlusion from the
// sun/moon, not from nearby geometry blocking ambient light).
//
// Samples come from a fixed, well-distributed spiral (a Vogel disk) laid
// out in a proper tangent-space hemisphere around the normal, rotated by
// a different angle per pixel using the same ordered 4x4 Bayer dither
// used for shadow/depth dithering elsewhere in this pack. This matters:
// an earlier version drew fully independent random directions per pixel
// per tap with no blur pass to clean the result back up, which produced
// harsh, scattered black speckling - a handful of unlucky, uncorrelated
// samples could swing one pixel straight to full occlusion while every
// neighboring pixel read completely different. A shared kernel that's
// just rotated per pixel keeps neighboring pixels' results close to each
// other, reading as a fine, even dither instead of black noise.
// Occlusion testing is done against depthtex1 (opaque geometry only),
// so translucent water/glass in front of something never counts as an
// occluder for it.
float computeSSAO(vec3 viewPos, vec3 viewNormal, vec2 uv) {
    const float radius = 0.9; // view-space units = blocks
    float occlusion = 0.0;

    // Stable tangent basis around the normal - avoids the old
    // "reflect if pointing the wrong way" trick, which visibly bunched
    // samples right at the hemisphere's equator instead of spreading
    // them evenly across it.
    vec3 up = (abs(viewNormal.z) < 0.99) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, viewNormal));
    vec3 bitangent = cross(viewNormal, tangent);

    float rotAngle = bayer4(gl_FragCoord.xy) * 6.2831853;
    float ca = cos(rotAngle);
    float sa = sin(rotAngle);

    for (int i = 0; i < SSAO_SAMPLES; i++) {
        float t = (float(i) + 0.5) / float(SSAO_SAMPLES);
        float spiralAngle = t * 6.2831853 * 2.4; // golden-angle-ish spiral turns
        float spiralRadius = sqrt(t);
        vec2 disk = vec2(cos(spiralAngle), sin(spiralAngle)) * spiralRadius;
        // Rotate the shared disk by this pixel's dither angle.
        vec2 rot = vec2(disk.x * ca - disk.y * sa, disk.x * sa + disk.y * ca);

        // Taller near the center taps (closer to the surface normal, so
        // most samples land close to the surface where contact occlusion
        // actually happens) with a few reaching further to the sides.
        float height = mix(0.25, 1.0, t);
        vec3 sampleDir = normalize(tangent * rot.x + bitangent * rot.y + viewNormal * height);
        vec3 samplePos = viewPos + sampleDir * radius * mix(0.2, 1.0, t);

        vec4 clip = gbufferProjection * vec4(samplePos, 1.0);
        if (clip.w <= 0.0) continue;
        vec2 sUV = (clip.xy / clip.w) * 0.5 + 0.5;
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) continue;

        float sceneDepthRaw = texture2D(depthtex1, sUV).r;
        if (sceneDepthRaw >= 0.9999) continue; // sky - never an occluder
        vec3 sceneViewPos = reconstructViewPos(sUV, sceneDepthRaw);

        // Occluded if real geometry at this screen position sits nearer
        // to the camera than our notional empty-space sample point.
        // rangeCheck fades the contribution out for surfaces far in
        // depth from the CENTER pixel, so unrelated distant geometry
        // can't falsely darken something right in front of the camera.
        //
        // Dividing by the fixed SSAO_SAMPLES below (not a running count
        // of how many samples were actually valid) is what fixes the
        // spurious full-black pixels: a sample that lands off-screen or
        // on the sky just contributes zero occlusion instead of being
        // excluded from the average entirely, so a pixel with only 2 of
        // 8 samples landing on-screen can no longer read as 100% occluded
        // just because both of those happened to hit something.
        float rangeCheck = clamp(radius / max(abs(viewPos.z - sceneViewPos.z), 0.0001), 0.0, 1.0);
        occlusion += (sceneViewPos.z >= samplePos.z + 0.025) ? rangeCheck : 0.0;
    }

    return 1.0 - clamp(occlusion / float(SSAO_SAMPLES), 0.0, 1.0);
}
#endif

#if WET_REFLECTIONS == 1
// Puddle-like screen-space reflections on wet, upward-facing terrain
// while it's raining. Structurally the same technique as
// gbuffers_water.fsh's screenSpaceReflection (march a reflected
// view-space ray, test it against the opaque depth buffer), but it has
// to run here as a post-process step instead of inside
// gbuffers_terrain.fsh directly: at the moment an opaque terrain
// fragment is being shaded, nothing else in the scene has been drawn
// into any buffer yet, so there's nothing to reflect yet. By the time
// composite.fsh runs, every gbuffer pass (including water) has already
// written colortex0, so this is the first point in the frame where
// "what does the world around this puddle look like" actually exists
// to sample.
vec4 wetSSR(vec3 viewPos, vec3 viewNormalDir) {
    vec3 viewDir = normalize(viewPos);
    vec3 rayDir = reflect(viewDir, viewNormalDir);
    if (rayDir.z > 0.0) return vec4(0.0);

    const int WET_SSR_STEPS = 12;
    float stepSize = 0.5;
    vec3 rayPos = viewPos + rayDir * 0.1;

    for (int i = 0; i < WET_SSR_STEPS; i++) {
        rayPos += rayDir * stepSize;

        vec4 clip = gbufferProjection * vec4(rayPos, 1.0);
        if (clip.w <= 0.0) break;
        vec2 sUV = (clip.xy / clip.w) * 0.5 + 0.5;
        if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) break;

        float sceneDepthRaw = texture2D(depthtex1, sUV).r;
        vec3 sceneViewPos = reconstructViewPos(sUV, sceneDepthRaw);

        if (rayPos.z <= sceneViewPos.z + 0.15 && sceneDepthRaw < 0.9999) {
            vec3 hitColor = texture2D(colortex0, sUV).rgb;
            float edgeFade = 1.0 - smoothstep(0.75, 1.0, max(abs(sUV.x - 0.5), abs(sUV.y - 0.5)) * 2.0);
            return vec4(hitColor, edgeFade);
        }
        stepSize *= 1.15;
    }
    return vec4(0.0);
}
#endif

vec3 computeGodRays(vec3 worldDirToFrag, float maxDist, vec2 uv) {
    // OPTIMIZATION: GODRAY_STRENGTH is a compile-time #define, so this
    // comparison folds to a compile-time constant - when it's 0 the
    // driver eliminates the raymarch loop below entirely instead of
    // running GODRAY_STEPS shadow-map taps per fragment just to multiply
    // the result by zero at the end.
    if (GODRAY_STRENGTH <= 0.0) return vec3(0.0);

    vec3 rayDir = normalize(worldDirToFrag);
    float marchDist = min(maxDist, SHADOW_DISTANCE * 0.9);

    int steps = GODRAY_STEPS;
    float stepSize = marchDist / float(steps);

    // Interleaved gradient noise, animated: without any temporal
    // accumulation in this pack, a dither pattern that's purely a
    // function of gl_FragCoord never changes from one frame to the
    // next, so it reads as a fixed stipple/halftone texture stamped
    // over the rays instead of natural light shimmer - that's a real
    // part of what was reading as "strange" rather than alive. Folding
    // a slow frame counter into the same hash keeps the same per-pixel
    // decorrelation (still no banding) while the actual dither offset
    // drifts continuously, so it reads as fine grain/shimmer instead of
    // a static printed pattern.
    vec2 fc = gl_FragCoord.xy + frameTimeCounter * 13.7;
    float dither = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
    vec3 samplePos = rayDir * stepSize * dither;

    float accum = 0.0;
    for (int i = 0; i < steps; i++) {
        vec3 shadowClip = worldToShadowClip(samplePos);
        float vis = sampleShadowPCF(shadowtex1, shadowClip);
        accum += vis;
        samplePos += rayDir * stepSize;
    }
    accum /= float(steps);

    vec3 lightDir = normalize(shadowLightPosition);
    float cosTheta = dot(rayDir, lightDir);
    // Stronger forward-scattering peak than before (0.7 -> 0.82) - real
    // crepuscular rays through gaps (tree canopy, window openings) read
    // as fairly narrow, defined shafts rather than a broad uniform
    // brightening across the whole view; the higher anisotropy
    // concentrates the visible brightening much more tightly around
    // looking straight down the light direction, which is what actually
    // makes it look like *rays* passing through occluders instead of a
    // general haze that happens to be strongest facing the sun.
    float scattering = phaseHG(cosTheta, 0.82) * 4.0 * PI;

    vec3 lightColor = getSunColor();
    float rainFade = 1.0 - rainStrength * 0.8;

    return accum * scattering * lightColor * GODRAY_STRENGTH * rainFade * 0.06;
}

// A compact, correctly-anchored glare disc centered on the sun/moon's
// actual on-screen position. shadowLightPosition is already a view-space
// DIRECTION (see note above), so projecting it through gbufferProjection
// gives the true screen-space location of the light source every frame -
// this is what makes the glare/shafts visibly track the sun as it moves,
// rather than being a fixed screen-space blob.
vec3 computeSunGlare(vec2 uv, bool isSky) {
    vec3 lightDir = normalize(shadowLightPosition);
    vec4 clipPos = gbufferProjection * vec4(lightDir * 10.0, 1.0);

    if (clipPos.w <= 0.0) return vec3(0.0); // light behind camera

    vec2 screenPos = (clipPos.xy / clipPos.w) * 0.5 + 0.5;

    // BUGFIX: this glow used to only check whether the CURRENT pixel
    // was sky, never whether the sun/moon ITSELF was actually visible
    // from the camera. That meant standing where the light source sat
    // behind a mountain, cloud, or any other solid geometry still
    // showed the full glare on every open-sky pixel nearby, since nothing
    // here ever looked at whether the source itself was in view - a big,
    // hard-edged, geometry-ignoring glow bleeding across the sky right
    // where terrain should have been blocking it. Sampling depthtex1
    // (opaque-only depth) at the light's own projected screen position
    // tells us that directly. A small soft-edged cluster of samples
    // instead of one single point avoids a hard on/off pop as the light
    // source's projected position crosses in and out from behind a
    // branch, leaf, or cloud edge frame to frame.
    float lightVisible = 1.0;
    if (screenPos.x > -0.05 && screenPos.x < 1.05 && screenPos.y > -0.05 && screenPos.y < 1.05) {
        vec2 clampedPos = clamp(screenPos, 0.0, 1.0);
        float visSum = 0.0;
        vec2 probeRadius = vec2(3.0) / vec2(viewWidth, viewHeight);
        visSum += step(0.9999, texture2D(depthtex1, clampedPos).r);
        visSum += step(0.9999, texture2D(depthtex1, clampedPos + vec2( probeRadius.x, 0.0)).r);
        visSum += step(0.9999, texture2D(depthtex1, clampedPos + vec2(-probeRadius.x, 0.0)).r);
        visSum += step(0.9999, texture2D(depthtex1, clampedPos + vec2(0.0,  probeRadius.y)).r);
        visSum += step(0.9999, texture2D(depthtex1, clampedPos + vec2(0.0, -probeRadius.y)).r);
        lightVisible = visSum / 5.0;
    }
    if (lightVisible <= 0.001) return vec3(0.0);

    vec2 aspectCorrectedUv = (uv - screenPos) * vec2(aspectRatio, 1.0);
    float d = length(aspectCorrectedUv);

    // Sunrise/sunset get a noticeably bigger, brighter glow than
    // midday - reference golden-hour shots read as dramatic largely
    // because of how much sky around the sun itself is glowing, not
    // just the sun disc.
    float duskBoost = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);

    // BUGFIX: at peak dusk this halo's decay coefficient dropped as low
    // as 3.0 while its brightness rose to 0.6 - through gaps in tree
    // canopy (many small openings near the sun's screen position, each
    // one a separate full-strength sample of this same glow) that
    // combination spread bright enough, wide enough, to blow out a large
    // fraction of the frame instead of reading as a contained golden-hour
    // glow around the sun itself. Kept the "bigger and brighter at dusk"
    // intent (real golden-hour skies do glow more than midday) but pulled
    // both ends in - still noticeably more dramatic than midday, just not
    // enough to swallow a third of the screen.
    float core = exp(-d * d * 1100.0) * 1.1;
    float halo = exp(-d * mix(7.0, 4.4, duskBoost)) * mix(0.28, 0.42, duskBoost);
    float glare = core + halo;

    // Soft radial sunburst rays through the glow, most visible at
    // golden hour - a stylized stand-in for anamorphic/atmospheric lens
    // rays rather than a physical simulation. Reads even over open sky,
    // unlike the volumetric god rays above which need actual geometry/
    // shadow occlusion along the view ray to show up at all.
    float angle = atan(aspectCorrectedUv.y, aspectCorrectedUv.x);
    float rayPattern = pow(abs(sin(angle * 6.0 + frameTimeCounter * 0.04)), 8.0);
    float rayFalloff = exp(-d * 2.6);
    glare += rayPattern * rayFalloff * duskBoost * 0.4;

    // Fade out through geometry (only a faint hint bleeds through solid
    // objects, most of the effect belongs to open sky/horizon views) and
    // fade with rain. lightVisible handles the light source's OWN
    // occlusion (see above); isSky still separately keeps the glare off
    // of solid foreground objects even when the light source itself
    // remains visible elsewhere in frame.
    glare *= mix(0.08, 1.0, float(isSky)) * (1.0 - rainStrength * 0.85) * lightVisible;
    glare *= (0.3 + 0.7 * getSunVisibility());

    return getSunColor() * glare * GODRAY_STRENGTH;
}

// Real raymarched volumetric clouds: intersects the view ray with a
// horizontal slab of world space, steps through it accumulating density
// from 3D fbm noise, and shades the result toward the sun/moon color
// weighted by how much density built up along the ray (a cheap
// single-scatter approximation - no separate shadow raymarch toward the
// sun, which would be far too expensive per-pixel here, but density-
// weighted forward scattering still gives clouds visible bright/dark
// sides relative to the light direction).
// Real raymarched volumetric clouds: intersects the view ray with a
// horizontal slab of world space, steps through it accumulating density
// from 3D fbm noise with Beer-Lambert attenuation and Powder-Sugar lighting.
vec3 computeVolumetricClouds(vec3 rayDir, vec3 baseColor, bool isSky) {
    if (!isSky) return baseColor;

    float horizonFade = smoothstep(0.0, 0.09, rayDir.y);
    if (horizonFade <= 0.001) return baseColor;

    const float cloudBase = 165.0;
    const float cloudTop  = 250.0;
    float camY = cameraPosition.y;

    float safeRayY = max(rayDir.y, 0.02);
    float tBase = (cloudBase - camY) / safeRayY;
    float tTop  = (cloudTop  - camY) / safeRayY;
    float tNearRaw = min(tBase, tTop);
    float tNear = clamp(tNearRaw, 0.0, 4000.0);
    float tFar  = max(tBase, tTop);
    if (tFar <= tNear) return baseColor;
    tFar = min(tFar, tNear + 900.0);

    float distanceFade = 1.0 - smoothstep(2200.0, 4000.0, tNearRaw);
    if (distanceFade <= 0.001) return baseColor;

    int steps = CLOUD_STEPS;
    float stepLen = (tFar - tNear) / float(steps);

    float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    float t = tNear + stepLen * dither;

    vec3 wind = vec3(frameTimeCounter * 0.9, 0.0, frameTimeCounter * 0.5);
    vec3 lightDir = normalize(shadowLightPosition);

    vec3 regionSamplePos = rayDir * tNear;
    vec2 regionCoord = (regionSamplePos.xz + cameraPosition.xz + wind.xz) * 0.0011;
    float regionNoise = cloudFBM(vec3(regionCoord, 0.35));
    float regionBias = (regionNoise - 0.5) * 0.30;

    float density = 0.0;
    float lightAccum = 0.0;
    float weightSum = 0.0;

    for (int i = 0; i < steps; i++) {
        vec3 samplePos = rayDir * t;
        vec3 cloudCoord = (samplePos + cameraPosition + wind + vec3(0.0, frameTimeCounter * 0.15, 0.0)) * 0.0055;
        float n = cloudFBM(cloudCoord);

        // High-frequency detail billows for fluffier cumulus cloud tops/edges
        float detail = perlinNoise3D(cloudCoord * 3.5 + vec3(frameTimeCounter * 0.05));
        n = mix(n, n * (0.8 + 0.4 * detail), 0.35);

        float heightFrac = clamp((camY + samplePos.y - cloudBase) / (cloudTop - cloudBase), 0.0, 1.0);
        float heightGradient = smoothstep(0.0, 0.12, heightFrac) * smoothstep(1.0, 0.5, heightFrac);
        float heightErosion = mix(0.0, 0.26, smoothstep(0.25, 1.0, heightFrac));

        float coverage = smoothstep(
            CLOUD_COVERAGE + heightErosion - regionBias,
            CLOUD_COVERAGE + heightErosion - regionBias + 0.34,
            n
        ) * heightGradient;

        // Beer-Lambert attenuation + Powder Sugar Effect for volumetric depth & glowing edges
        float sampleDensity = coverage * stepLen * 0.04;
        density += sampleDensity * (1.0 - density);
        
        float cosTheta = dot(rayDir, lightDir);
        float dualLobePhase = phaseHG(cosTheta, 0.65) * 0.75 + phaseHG(cosTheta, -0.30) * 0.25;
        float powderEffect = 1.0 - exp(-sampleDensity * 3.5);
        lightAccum += coverage * dualLobePhase * powderEffect;
        weightSum += coverage;

        t += stepLen;
    }

    density = clamp(density, 0.0, CLOUD_OPACITY);
    if (density < 0.01) return baseColor;

    float forwardScatter = weightSum > 0.0 ? clamp(lightAccum / weightSum * 4.0 * PI, 0.0, 1.0) : 0.0;
    float beerAttenuation = exp(-density * 1.8);
    vec3 sunLit = getSunColor() * (0.45 + 1.25 * forwardScatter) * mix(0.35, 1.0, beerAttenuation);
    vec3 cloudColor = mix(getAmbientSkyColor() * 1.15, sunLit, 0.65);
    cloudColor *= mix(1.0, 0.4, rainStrength);

    float nightFactor = 1.0 - getDayFactor();
    float edgeRim = (1.0 - smoothstep(0.0, 0.6, density)) * forwardScatter;
    vec3 moonSheen = vec3(0.65, 0.72, 0.85) * edgeRim * nightFactor * NIGHT_CLOUD_GLOW * 0.8;
    cloudColor += moonSheen;

    float duskFactor = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);
    vec3 duskRim = getSunColor() * edgeRim * duskFactor * NIGHT_CLOUD_GLOW * 0.6;
    cloudColor += duskRim;

    cloudColor *= (0.12 + 0.65 * getDayFactor() + 0.25 * getSunVisibility()) + nightFactor * 0.10 * NIGHT_CLOUD_GLOW;

    return mix(baseColor, cloudColor, density * horizonFade * distanceFade);
}

// ---------------------------------------------------------------------
// Night atmospheric fog - a light, noise-driven ground haze visible at
// night, independent of the regular distance fog.
// ---------------------------------------------------------------------
vec3 applyNightAtmosphericFog(vec3 color, vec3 worldPos, float dist, bool isSky) {
    if (isSky || NIGHT_FOG_STRENGTH <= 0.0) return color;
    float nightFactor = 1.0 - getDayFactor();
    if (nightFactor <= 0.01) return color;

    vec3 absoluteWorld = mod(worldPos + cameraPosition, 10000.0);
    float drift = frameTimeCounter * 0.015;
    float mistNoise = cloudFBM(vec3(absoluteWorld.xz * 0.02 + drift, drift * 0.5));

    float density = (1.0 - exp(-dist * 0.012)) * mix(0.55, 1.0, mistNoise);
    float heightFalloff = exp(-max(worldPos.y + 2.0, 0.0) * 0.05);
    density *= heightFalloff;

    density *= nightFactor * NIGHT_FOG_STRENGTH;
    density = clamp(density, 0.0, 0.55);
    if (density < 0.005) return color;

    vec3 fogTint = mix(vec3(0.045, 0.06, 0.11), vec3(0.09, 0.12, 0.19), mistNoise);
    return mix(color, fogTint, density);
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

    if (depth < 0.9999) {
        vec3 viewLightDir = normalize(shadowLightPosition);
        vec3 viewDirToCam = normalize(-viewPos);
        float grazing = 1.0 - clamp(dot(viewNormal, viewDirToCam), 0.0, 1.0);
        float rim = smoothstep(0.72, 0.97, grazing);
        float facing = clamp(dot(viewNormal, viewLightDir) * 0.5 + 0.5, 0.0, 1.0);
        color += getSunColor() * rim * facing * 0.09 * (0.5 + 0.5 * getSunVisibility());
    }

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

#if WET_REFLECTIONS == 1
    bool isEmissiveSurface = normalSample.a > 0.5;
    if (depth < 0.9999 && wetness > 0.01 && !isEmissiveSurface) {
        float opaqueDepth = texture2D(depthtex1, texcoord).r;
        if (abs(depth - opaqueDepth) < 0.0005) {
            vec3 worldNormalDir = normalize((gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz);
            if (worldNormalDir.y > 0.8) {
                float skyLight = texture2D(colortex3, texcoord).a;
                float skyExposure = smoothstep(0.3, 0.75, skyLight);

                vec2 puddleCoord = worldPos.xz + cameraPosition.xz;
                float puddleMask = valueNoise3D(vec3(puddleCoord * 0.15, 0.0));
                puddleMask = smoothstep(0.35, 0.7, puddleMask);
                float wetFactor = wetness * puddleMask * skyExposure * WET_REFLECTIONS_STRENGTH;

                if (wetFactor > 0.01) {
                    vec3 puddleViewDir = normalize(-viewPos);
                    float puddleNdotV = clamp(dot(viewNormal, puddleViewDir), 0.0, 1.0);
                    float puddleFresnel = clamp(pow(1.0 - puddleNdotV, 4.0) * 0.85 + 0.08, 0.0, 0.9);

                    vec4 wr = wetSSR(viewPos, viewNormal);
                    vec3 puddleReflection = mix(getAmbientSkyColor(), wr.rgb, wr.a);

                    float blend = clamp(puddleFresnel * wetFactor, 0.0, 0.92);
                    color = mix(color, puddleReflection, blend);
                }
            }
        }
    }
#endif

    // BUGFIX: Use opaque depth (depthtex1) to evaluate isSky instead of depthtex0,
    // because sun/moon geometry drawn in sky passes writes to depthtex0 (depth ~0.999),
    // which caused a sharp rectangular boundary discontinuity around the sun/moon disc.
    float opaqueDepthSample = texture2D(depthtex1, texcoord).r;
    bool isSky = opaqueDepthSample >= 0.9999;
    float marchDist = isSky ? SHADOW_DISTANCE * 0.9 : dist;

    color = computeVolumetricClouds(normalize(worldPos), color, isSky);

    vec3 godRays = computeGodRays(worldPos, marchDist, texcoord);
    color += godRays;
    color += computeSunGlare(texcoord, isSky);

    // New feature: light atmospheric ground haze at night - see
    // applyNightAtmosphericFog above. Applied after god rays/glare so
    // it settles over them the way real mist would sit in front of
    // distant light sources, not fight to peek through on top of it.
    color = applyNightAtmosphericFog(color, worldPos, dist, isSky);


    // --- New feature: fireflies over forest/jungle/swamp/taiga ground
    // at night. A per-pixel procedural field (see fireflyField in
    // common.glsl) rather than an actual particle system, run here as a
    // post-process since it needs the full reconstructed world position
    // and depth this pass already has on hand for everything else.
#if FIREFLIES == 1
    if (!isSky && FIREFLY_STRENGTH > 0.0) {
        bool fireflyBiome = (biome_category == CAT_FOREST || biome_category == CAT_JUNGLE
                           || biome_category == CAT_SWAMP  || biome_category == CAT_TAIGA);
        float nightFactor = 1.0 - getSunVisibility();
        // Roughly ground/undergrowth height relative to the camera, and
        // a modest render distance - fireflies are a close-range detail,
        // not something that should try to populate the whole horizon.
        if (fireflyBiome && nightFactor > 0.4 && dist < 40.0 && abs(worldPos.y) < 4.0) {
            vec3 absoluteWorld = mod(worldPos + cameraPosition, 10000.0);
            float firefly = fireflyField(absoluteWorld, frameTimeCounter);
            float distFade = 1.0 - smoothstep(28.0, 40.0, dist);
            vec3 fireflyColor = vec3(0.85, 1.0, 0.35);
            color += fireflyColor * firefly * nightFactor * distFade * FIREFLY_STRENGTH * 1.5;
        }
    }
#endif

    // Distant atmosphere haze toward the skyline, strongest at sunset/sunrise.
    //
    // BUGFIX: this used to blend distant terrain toward
    // `getSunColor()*0.5 + getAmbientSkyColor()*0.5`. At most times of day
    // that average sits close to (0.9, 0.9, 0.9) - both inputs are
    // themselves fairly bright/desaturated - so anything far enough away
    // to pick up meaningful haze (distant ruins, mountains, structures
    // peeking over the horizon) washed out toward a flat near-white
    // instead of a believable hazy-blue atmosphere color. getHorizonSkyColor()
    // is the function this file already uses for exactly this purpose
    // elsewhere (see applyFog's far-fog blend below) - a real
    // time-of-day-correct horizon gradient instead of an arbitrary
    // average of two unrelated lighting terms.
    float duskHaze = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);
    float hazeAmount = clamp(dist / (SHADOW_DISTANCE * 2.2), 0.0, 1.0) * (0.08 + duskHaze * 0.18);
    color = mix(color, getHorizonSkyColor(), hazeAmount * (1.0 - float(isSky)));

    // Underwater visibility falloff: real water scatters/absorbs light
    // with distance even when it's clear, so sight underwater should
    // still fade out with depth of view instead of staying perfectly
    // sharp all the way to render distance the way it did before. Uses
    // vanilla's own `fogColor` uniform rather than a hardcoded color -
    // Minecraft already sets that to the correct underwater blue/green
    // (or swamp-water tint, etc.) for whatever water the eye is in, so
    // this stays correct across biomes without guessing a fixed color.
    if (isEyeInWater == 1) {
        float underwaterFog = 1.0 - exp(-dist * 0.035 * UNDERWATER_FOG_DENSITY);
        color = mix(color, fogColor, underwaterFog * 0.55);

        // BUGFIX: this used to call computeGodRays() a SECOND time here
        // with identical arguments to the call already made above for
        // the regular scene god rays - a full extra shadow-map raymarch
        // computing the exact same underlying value, then tinted and
        // multiplied by 1.8 on top of the base pass that was already
        // added to `color` once. Right at a water surface's own screen-
        // space silhouette, a shadow-map raymarch is especially prone to
        // depth-discontinuity edge artifacts (the ray's samples straddle
        // a sharp jump between "just above the water" and "just below
        // it"); doubling that same raymarch's contribution and boosting
        // it 1.8x is what was reading as a bright, glowing halo hugging
        // the water's edges, worst at night since a dark backdrop makes
        // any stray brightness there far more visible. Reusing the
        // single already-computed `godRays` value (no second raymarch)
        // and toning the extra underwater push down fixes both the
        // redundant GPU cost and the edge artifact at once.
        if (UNDERWATER_GODRAYS_STRENGTH > 0.0 && GODRAY_STRENGTH > 0.0) {
            // Wavy caustic-net modulation so the shafts look bent by the
            // moving surface above instead of perfectly straight beams -
            // reuses the same causticPattern already driving seabed
            // caustics and the underwater screen shimmer in final.fsh.
            float ripple = 0.6 + 0.4 * causticPattern(worldPos.xz + cameraPosition.xz, frameTimeCounter);
            vec3 shaftColor = vec3(0.55, 0.85, 1.0); // cool blue-white, not the raw warm sun color
            color += godRays * shaftColor * ripple * UNDERWATER_GODRAYS_STRENGTH * 0.5;
        }
    }

    gl_FragData[0] = vec4(color, sceneColor.a);
}
