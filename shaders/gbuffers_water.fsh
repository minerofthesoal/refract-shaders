#version 120
/* Refract Shaders - gbuffers_water.fsh
   Water v2 - rebuilt from scratch around the BSL / Complementary
   Unbound look instead of tuning the old system further:

     - Mesh is completely flat now (see gbuffers_water.vsh); every bit
       of "wave" is a per-pixel fake normal, so the old tearing/shard
       artifact is structurally gone, not just smaller.
     - Crystal-clear shallows: alpha ramps up with depth instead of
       being a near-constant near-opaque value, so you can actually see
       the bottom near shore like in Bloop/Complementary/BSL reference
       shots, with a saturated turquoise->teal->deep-blue gradient as
       depth increases.
     - Fresnel pushed harder toward full mirror at grazing angles for
       the glossy/reflective look those packs have.
     - Added a scattered sparkle/glint layer (waterSparkle) on top of
       the normal sun highlight - the field of tiny twinkling dots
       raking across the surface is a very recognizable BSL/
       Complementary signature that a single specular lobe can't
       reproduce on its own.
     - Depth-gradient dithering to avoid 8-bit banding on the
       transparency ramp.

   As before: the surface-specific stuff (fresnel, depth tint, foam,
   glint, sparkle) only applies to actual top-facing water
   (`topSurface`) - shaft walls and underwater faces get simple
   uniform shading, since applying surface-facing math to vertical
   geometry is what caused the hard banding seen in earlier
   screenshots. */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D depthtex1;
uniform sampler2D colortex3; // opaque-scene copy, used by water's SSR

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldNormal;
varying vec3 worldPos;
varying vec3 shadowClipPos;
varying float blockId;
varying float isWater;

/* RENDERTARGETS: 0,1 */

vec3 reconstructViewPosFromDepth(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clip;
    viewPos /= viewPos.w;
    return viewPos.xyz;
}

// RESTORED for water's exclusive use (glass keeps the simple fixed sky
// reflection - this was pulled from both at one point while chasing the
// colortex3 corruption history, but water wants the real thing back).
// Marches the reflected view-space ray forward, projects each sample
// back to screen space, and checks it against the opaque depth buffer
// (depthtex1 - captured before translucents, so the water surface
// itself doesn't self-occlude the ray). Returns rgb = reflection color,
// a = hit confidence (0 = no hit, use the sky/ambient fallback instead).
#define SSR_STEPS 16
vec4 screenSpaceReflection(vec3 viewPos, vec3 viewNormalDir) {
    vec3 viewDir = normalize(viewPos);
    vec3 rayDir = reflect(viewDir, viewNormalDir);

    // Only bother marching forward-facing reflections (into the screen).
    if (rayDir.z > 0.0) return vec4(0.0);

    float stepSize = 0.5;
    vec3 rayPos = viewPos + rayDir * 0.1;
    vec3 prevRayPos = rayPos;

    for (int i = 0; i < SSR_STEPS; i++) {
        prevRayPos = rayPos;
        rayPos += rayDir * stepSize;

        vec4 clip = gbufferProjection * vec4(rayPos, 1.0);
        if (clip.w <= 0.0) break;
        vec2 screenUV = (clip.xy / clip.w) * 0.5 + 0.5;

        if (screenUV.x < 0.0 || screenUV.x > 1.0 || screenUV.y < 0.0 || screenUV.y > 1.0) break;

        float sceneDepthRaw = texture2D(depthtex1, screenUV).r;
        vec3 sceneViewPos = reconstructViewPosFromDepth(screenUV, sceneDepthRaw);

        if (rayPos.z <= sceneViewPos.z + 0.15 && sceneDepthRaw < 0.9999) {
            // Binary-search back between the last miss (prevRayPos) and
            // this hit (rayPos) to converge on the actual intersection
            // instead of accepting the coarse, likely-overshot step
            // position outright.
            vec3 lo = prevRayPos;
            vec3 hi = rayPos;
            for (int r = 0; r < 5; r++) {
                vec3 mid = mix(lo, hi, 0.5);
                vec4 midClip = gbufferProjection * vec4(mid, 1.0);
                vec2 midUV = (midClip.xy / midClip.w) * 0.5 + 0.5;
                float midDepthRaw = texture2D(depthtex1, midUV).r;
                vec3 midScenePos = reconstructViewPosFromDepth(midUV, midDepthRaw);
                if (mid.z <= midScenePos.z + 0.15 && midDepthRaw < 0.9999) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }

            vec4 hitClip = gbufferProjection * vec4(hi, 1.0);
            vec2 hitUV = (hitClip.xy / hitClip.w) * 0.5 + 0.5;
            // sanitizeColor guards against a NaN/runaway colortex3 value
            // ever reaching the bloom mip chain. The depthtex1 < 0.9999
            // checks above (both the coarse hit test and every binary-
            // refine step) already guarantee this UV never lands on an
            // unwritten sky pixel, which was the actual root cause of
            // the mosaic corruption this pack saw - this is defense in
            // depth on top of that, not instead of it.
            vec3 hitColor = sanitizeColor(texture2D(colortex3, hitUV).rgb);
            float edgeFade = 1.0 - smoothstep(0.75, 1.0, max(abs(hitUV.x - 0.5), abs(hitUV.y - 0.5)) * 2.0);
            return vec4(hitColor, edgeFade);
        }

        stepSize *= 1.1;
    }

    return vec4(0.0);
}

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;

    vec3 normal = normalize(viewNormal);
    // Was checking the VIEW-space normal.y here, which only lines up
    // with "facing up in the world" when the camera happens to be
    // roughly level. Looking straight down at water rotates that
    // view-space frame so a true top-facing surface's normal.y drifts
    // toward 0 and this test wrongly failed, dropping into the plain
    // wall-tint branch below - i.e. water looking straight down at it
    // fell back to a flat, undetailed look instead of the full
    // fresnel/reflection/sparkle treatment. worldNormal.y stays 1.0 for
    // a horizontal water surface regardless of camera angle, so it's
    // the correct thing to gate this on.
    bool topSurface = (isWater > 0.5 && worldNormal.y > 0.3);
    vec3 combinedN = vec3(0.0, 1.0, 0.0);
    vec2 worldXZ = worldPos.xz + cameraPosition.xz;

    if (topSurface) {
        // Broad layered waves (waterWaveNormal) + fine close-up ripple
        // detail (waterRippleNormal) on top. Both are pure per-pixel
        // math against a flat mesh - no vertex displacement anywhere,
        // so there is nothing here that can tear.
        vec3 broadN = waterWaveNormal(worldXZ, frameTimeCounter);
        vec3 rippleN = waterRippleNormal(worldXZ, frameTimeCounter);
        combinedN = normalize(broadN + rippleN * 0.18);

        // Rain ripples layer on top, scaled by how hard it's raining -
        // wetness is already a smoothed 0..1 rain intensity, so this
        // fades in/out gradually along with the actual weather instead
        // of snapping on the instant rain starts.
        if (wetness > 0.01) {
            vec3 rainN = rainRippleNormal(worldXZ, frameTimeCounter);
            combinedN = normalize(mix(combinedN, rainN, wetness * 0.35 * RAIN_RIPPLE_STRENGTH));
        }

        vec3 viewN = normalize(mat3(gbufferModelView) * combinedN);
        normal = normalize(mix(normal, viewN, 0.9));

        vec2 rippleUV = texcoord + combinedN.xz * 0.028;
        albedo = texture2D(gtexture, rippleUV) * vColor;
    }

    vec3 viewLightDir = normalize(shadowLightPosition);
    float NdotL = max(dot(normal, viewLightDir), 0.0);

    float shadow = sampleShadowPCF(shadowtex1, shadowClipPos, slopeScaledBias(NdotL));
    // Real canopy darkening under leaves (a pond under a tree canopy
    // should read dappled, not flat-lit) - see translucentCanopyOcclusion
    // in common.glsl. Applied before the distance fade below so both PCF
    // samples it compares are on the same raw, un-faded footing.
    shadow *= translucentCanopyOcclusion(shadowtex0, shadowClipPos, slopeScaledBias(NdotL), shadow);
    shadow = mix(shadow, 1.0, shadowDistanceFadeFactor(worldPos));
    // BUGFIX: this whole block used to also run for glass, sampling
    // shadowcolor0 at (or very near) glass's own position in the shadow
    // map. For an isolated glass block, that position IS glass's own
    // colored-caster entry - two earlier attempts tried to prevent this
    // by comparing against shadowtex0's depth before falling through to
    // a "bleed" sample, but that fallback samples a small radius around
    // the same xy, which for a single block often still lands back on
    // its own texel. The conceptual issue is deeper than the sampling
    // math: this mechanic exists to color light landing on OTHER
    // surfaces behind/near colored glass (handled in
    // gbuffers_terrain.fsh/gbuffers_entities.fsh, both unaffected by
    // this change) - it was never meant to reapply to the glass
    // fragment's own shading, which is what was reading as the tint
    // being "stuck inside" the glass itself. Restricting this entire
    // block to water only is more robust than continuing to patch the
    // sampling condition.
    vec3 shadowTint = vec3(1.0);
    if (isWater > 0.5) {
        float casterDepth = texture2D(shadowtex0, shadowClipPos.xy).r;
        if (shadowClipPos.z - casterDepth > 0.0025) {
            // PCF-filtered - see the matching note + sampleShadowTintPCF
            // in common.glsl (fixes the hard-edged/blocky colored patch).
            vec4 tint = sampleShadowTintPCF(shadowcolor0, shadowClipPos.xy);
            shadowTint = computeShadowTint(tint, worldPos);

            // Glass "skylight" shadow - see the matching note in
            // gbuffers_terrain.fsh: glass dims direct light a bit
            // rather than only recoloring it.
            shadow *= mix(1.0, 0.45, GLASS_SKYLIGHT_STRENGTH * clamp(tint.a, 0.0, 1.0));
        } else if (GLASS_BLEED_STRENGTH > 0.0) {
            // Colored-light bleed onto nearby surfaces - see the
            // matching note + sampleShadowTintBleed in common.glsl.
            vec4 bleed = sampleShadowTintBleedDynamic(shadowcolor0, shadowClipPos.xy);
            vec3 bleedTint = computeShadowTint(bleed, worldPos);
            shadowTint = mix(vec3(1.0), bleedTint, GLASS_BLEED_STRENGTH * 0.5);
        }
    }

    vec3 sunColor = getSunColor() * (0.6 + 0.55 * getSunVisibility());
    // No baseline floor - a fully unlit body of water (sealed cave,
    // night with zero sky exposure) now genuinely goes dark instead of
    // always keeping 40% sky ambient regardless of enclosure. See the
    // matching note in gbuffers_terrain.fsh.
    // BUGFIX: ambient now picks up shadowTint too, matching direct - see
    // the detailed note in gbuffers_terrain.fsh. Without this, colored
    // glass/ice only visibly tinted its light patch while direct sun hit
    // it; under overcast/rainy ambient-dominated light it read as the
    // sky's own blue-gray ambient color instead of its own tint.
    vec3 ambient = getAmbientSkyColor() * lmcoord.y * mix(0.8, 1.0, shadow) * shadowTint;
    vec3 direct = sunColor * NdotL * shadow * shadowTint * lmcoord.y * cloudShadowFactor(worldPos);

    vec3 lighting = ambient + direct;
    lighting = softenHighlights(lighting);
    vec3 color = albedo.rgb * lighting;
    float outAlpha = albedo.a;

    // How much actual light is reaching this water at all, 0..1. Used
    // below to keep the stylized depth-tint/reflection colors from
    // showing up at full brightness in the dark - a pretty turquoise
    // tint has no business being clearly visible with no light source
    // nearby, the same way the actual terrain isn't.
    float lightLevel = clamp(dot(ambient + direct, vec3(0.333)) / 0.22, 0.0, 1.0);
#if TRUE_BLACK_NIGHTS == 1
    float tintFloor = 0.0;
#else
    float tintFloor = 0.05;
#endif
    float tintVisibility = mix(tintFloor, 1.0, lightLevel);

    if (topSurface) {
        vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);

        // Small blur on the terrain depth used for the tint/foam ramp
        // only (not the SSR trace below, which needs the real depth) -
        // softens the hard staircase edges you get where the underlying
        // terrain itself is physically stepped, which otherwise show up
        // as sharp bands in the depth-based color instead of a smooth
        // gradient.
        float terrainDepthRaw = texture2D(depthtex1, screenUV).r;
        float depthBlur = terrainDepthRaw;
        depthBlur += texture2D(depthtex1, screenUV + texelSize * vec2( 1.5,  0.5)).r;
        depthBlur += texture2D(depthtex1, screenUV + texelSize * vec2(-1.5,  0.5)).r;
        depthBlur += texture2D(depthtex1, screenUV + texelSize * vec2( 0.5, -1.5)).r;
        depthBlur += texture2D(depthtex1, screenUV + texelSize * vec2(-0.5,  1.5)).r;
        depthBlur *= 0.2;

        vec3 terrainViewPos = reconstructViewPosFromDepth(screenUV, depthBlur);
        vec3 waterViewPos = reconstructViewPosFromDepth(screenUV, gl_FragCoord.z);
        float waterDepth = max(length(terrainViewPos - waterViewPos), 0.0);

        // Dither the depth ramp itself (not just the final color) so
        // the shallow->deep transition doesn't band once it's quantized
        // to 8 bits for the transparency/color output.
        float ditherOffset = (bayer4(gl_FragCoord.xy) - 0.5) * 0.35;
        // Reaches "fully deep" over roughly twice the distance as
        // before (was /6.0) - reference-grade clear water (the kind
        // where you can see terrain detail several blocks down) stays
        // legible for much longer before the tint takes over entirely.
        float depthFactor = clamp((waterDepth + ditherOffset) / (11.0 * WATER_CLARITY), 0.0, 1.0);

        // Bright turquoise shallows -> teal -> deep saturated blue,
        // matching the Bloop/Complementary/BSL reference look rather
        // than a muted realistic tint. Shallow tint brightened slightly
        // for a crisper, sunlit-tropical-water read.
        vec3 shallowTint = vec3(0.20, 0.78, 0.74);
        vec3 midTint      = vec3(0.05, 0.34, 0.48);
        vec3 deepTint     = vec3(0.010, 0.09, 0.22);
        // BUGFIX: multiplying the fixed teal base by biomeHue (vColor
        // normalized to just its hue) wasn't enough to actually
        // differentiate ocean types - vanilla's own warm ocean
        // (aquamarine) and cold ocean (deep blue) colors are both
        // green/blue-dominant like the fixed teal base already is, so
        // multiplying by their hues barely shifted the result, and
        // hue-normalization throws away the absolute color that
        // actually distinguishes them in the first place. Blending
        // toward vColor's real RGB (not just its hue) for the shallow/
        // mid range gives real separation between ocean variants -
        // deep water stays close to the fixed dark base regardless of
        // biome, matching how real water genuinely does converge
        // toward uniform darkness at depth no matter its surface color.
        vec3 biomeShallow = mix(shallowTint, vColor.rgb * 1.15, 0.8);
        vec3 biomeMid = mix(midTint, vColor.rgb * 0.55, 0.7);
        vec3 depthTint = mix(mix(biomeShallow, biomeMid, clamp(depthFactor * 2.0, 0.0, 1.0)),
                              deepTint, clamp(depthFactor * 2.0 - 1.0, 0.0, 1.0));

        // BUGFIX: swamp water was reading as clear/blue-ish instead of the
        // murky green it should be. The biome color blend above IS real
        // (vColor carries vanilla's actual dark swamp-green water color),
        // but two other things were washing it out: this pack's whole
        // water system was built around a "crystal clear, see the seabed"
        // look (Round 5's WATER_CLARITY extension + a low 0.22 alpha
        // floor), which applies identically regardless of biome, and
        // swamp water is almost always shallow (a block or two), so
        // depthFactor rarely climbs high enough for the biome-tinted
        // shallow/mid colors above to dominate - most of a swamp puddle's
        // color comes from `color` (the barely-tinted raw water texture)
        // via baseWater's mix below, not from this depthTint at all. Real
        // swamp water is thick with algae/tannins and doesn't stay clear
        // no matter how shallow it is. Pushing swamp specifically toward
        // its own murky-dark color here, and separately lowering how much
        // seabed shows through (the alpha floor below), fixes both halves
        // of why it wasn't reading as swampy.
        if (biome_category == CAT_SWAMP) {
            vec3 swampMurk = vColor.rgb * vec3(0.55, 0.62, 0.42); // darker, yellow-green shifted
            float murkAmount = clamp(0.55 * SWAMP_MURKINESS, 0.0, 0.95);
            depthTint = mix(depthTint, swampMurk, murkAmount);
        }

        // Extra warm-tropical / icy-pale push on ocean water beyond the
        // existing vColor blend - see getOceanTemperatureTint in
        // common.glsl for why vColor alone doesn't separate ocean variants
        // as much as it could.
        depthTint = getOceanTemperatureTint(depthTint, vColor.rgb);
        depthTint *= tintVisibility;

        vec3 viewDirToCam = normalize(mat3(gbufferModelView) * normalize(-worldPos));
        float NdotV = clamp(dot(normal, viewDirToCam), 0.0, 1.0);

        // Harder push toward a full mirror at grazing angles than
        // before - this is most of what makes reference shaderpack
        // water read as glossy/glassy instead of matte.
        float fresnel = pow(1.0 - NdotV, 5.0);
        fresnel = clamp(fresnel * 0.92 + 0.06, 0.0, 0.98);
        fresnel = clamp(fresnel * WATER_REFLECTION_STRENGTH, 0.0, 0.98);
        // Swamp water is thick with algae/tannins and doesn't mirror the
        // sky cleanly the way clear water does - it scatters light
        // diffusely instead. Without this, a bright overcast/rainy sky
        // (swamp's usual weather) reflects strongly enough to wash the
        // murky color back out into a pale haze, undoing the murkiness
        // work above.
        if (biome_category == CAT_SWAMP) {
            fresnel *= clamp(1.0 - 0.5 * SWAMP_MURKINESS, 0.15, 1.0);
        }

        // RESTORED: water gets real SSR back (glass keeps the simple
        // fixed sky reflection - see its own comment at that call site
        // for why it's staying that way).
        vec4 ssr = screenSpaceReflection(waterViewPos, normal);
        ssr.a *= 0.75;
        vec3 skyRefl = mix(getAmbientSkyColor(), sunColor, 0.32) * tintVisibility;
        vec3 reflection = mix(skyRefl, ssr.rgb, ssr.a);

        // Signature "Refract" touch: a subtle prismatic fringe at
        // grazing angles, evoking real chromatic dispersion (different
        // wavelengths bending by slightly different amounts through a
        // refractive interface) instead of a perfectly neutral-colored
        // mirror edge. This is a stylized tint approximation rather
        // than a true per-wavelength re-trace (which would mean
        // marching the SSR ray three separate times, once per color
        // channel) - kept deliberately subtle so it reads as a bit of
        // a sheen rather than an obvious rainbow.
        if (CHROMATIC_DISPERSION_STRENGTH > 0.0) {
            float fringe = pow(fresnel, 4.0) * CHROMATIC_DISPERSION_STRENGTH;
            vec3 dispersionTint = vec3(1.0 + fringe * 0.08, 1.0 - fringe * 0.02, 1.0 - fringe * 0.10);
            reflection *= dispersionTint;
        }

        // Crystal-clear near shore: let the refracted seabed show
        // through strongly in shallow water and fade to the deep tint
        // as depth increases, instead of a near-constant heavy tint.
        // Softer ramp than before (was *1.4) - shallow water now stays
        // mostly untinted for noticeably longer, matching reference
        // shots where seabed detail is still clearly readable several
        // blocks down.
        //
        // Swamp water shouldn't follow this same crystal-clear ramp: real
        // swamp water is murky at ANY depth, not just once it's deep
        // enough to hit the pack's usual "fully tinted" threshold - swamp
        // puddles are typically only 1-3 blocks deep and would otherwise
        // never reach that threshold at all. A separate, much steeper
        // ramp (mostly murk almost immediately) fixes that without
        // touching the crystal-clear look everywhere else.
        float waterTintBlend = clamp(depthFactor * 0.95, 0.0, 1.0);
        if (biome_category == CAT_SWAMP) {
            waterTintBlend = clamp(waterTintBlend + 0.6 * SWAMP_MURKINESS, 0.0, 1.0);
        }
        vec3 baseWater = mix(color, depthTint, waterTintBlend);

        #if WATER_REFLECTION_MODE == 3
            color = baseWater; // reflections disabled outright
        #else
            color = mix(baseWater, reflection, fresnel);
        #endif

        // Alpha follows the same crystal-clear -> opaque depth ramp,
        // so shallows are genuinely see-through instead of just
        // tinted-but-still-opaque. Floor dropped from 0.40 to 0.22 -
        // the old floor was still noticeably more opaque than the
        // reference "can see the sandy bottom clearly" look even at
        // minimum depth.
        outAlpha = mix(0.22, 0.88, depthFactor);
        outAlpha = mix(outAlpha, 0.94, fresnel * 0.35);
        // Swamp water is thick enough that you genuinely can't see the
        // bottom clearly even in shallows - raise its opacity floor
        // separately from the alpha ramp everything else uses.
        if (biome_category == CAT_SWAMP) {
            outAlpha = clamp(max(outAlpha, 0.55 * SWAMP_MURKINESS), 0.0, 0.92);
        }

        // Shoreline foam - narrow band, sparse coverage.
        float shoreFactor = 1.0 - smoothstep(0.0, 0.35, waterDepth);
        if (shoreFactor > 0.01) {
            vec2 foamUV = worldPos.xz * 3.0 + frameTimeCounter * 0.35;
            float foamNoise = hash12(floor(foamUV * 8.0) / 8.0);
            float foamLine = smoothstep(0.72, 0.88, foamNoise) * shoreFactor * WATER_FOAM_STRENGTH;
            foamLine = clamp(foamLine, 0.0, 1.0);
            color = mix(color, vec3(0.95, 0.98, 1.0), foamLine * 0.5);
            outAlpha = mix(outAlpha, min(outAlpha + 0.3, 1.0), foamLine);
        }

        // Wave-crest whitecaps on open water, not just the shoreline -
        // gives large bodies of water some life instead of a perfectly
        // smooth gradient everywhere past the shore foam band. Driven
        // by the wave normal's own tilt (a steep local slope reads as
        // a "crest") and scaled up with wetness so choppier, rainy
        // weather shows visibly more whitecaps, the way real open
        // water does.
        float waveSteepness = 1.0 - combinedN.y;
        float crestNoise = hash12(floor(worldXZ * 2.2 + frameTimeCounter * 0.15));
        float whitecap = smoothstep(0.22, 0.36, waveSteepness) * step(0.6, crestNoise);
        whitecap *= mix(0.15, 1.0, wetness) * WATER_FOAM_STRENGTH;
        whitecap = clamp(whitecap, 0.0, 1.0);
        color = mix(color, vec3(0.95, 0.98, 1.0), whitecap * 0.4);

        // Sun glint: tight bright core + softer broad lobe, same as
        // before, PLUS a scattered sparkle layer of tiny twinkling
        // highlight dots along the same reflection direction - this is
        // the "glitter" that reads distinctly as BSL/Complementary
        // rather than a single smooth highlight.
        vec3 reflectDir = reflect(-viewLightDir, normal);
        float specDot = max(dot(reflectDir, viewDirToCam), 0.0);
        float specCore = pow(specDot, 260.0);
        float specSoft = pow(specDot, 30.0) * 0.14;

        // Wider angular gate than before (was 0.85-0.995, a single
        // tight glinting patch) so sparkle reads across a broad swath
        // of the surface facing roughly toward the sun, matching
        // reference shots of a wide scattered glitter field rather than
        // one concentrated highlight - while leaving waterSparkle's own
        // per-cell size/activation-rate alone, since a wider mask on
        // TOP of denser/bigger individual points is what previously
        // washed out into a flat hazy sheen instead of distinct twinkles.
        float sparkleMask = smoothstep(0.55, 0.99, specDot);
        float sparkle = waterSparkle(worldXZ, frameTimeCounter) * sparkleMask;

        // BUGFIX: sunColor at night is not zero (moon gives vec3(0.05,0.07,0.13)),
        // so specular glint and sparkle on water were visibly bright at night,
        // especially near water edges where the bloom pass then made them glow.
        // Gate glint/sparkle by getSunVisibility() so they correctly fade to near-
        // zero at night, matching the visual expectation that water sparkles are
        // a sun-only effect (the moon highlight is subtle and picked up by `direct`).
        float glintDay = getSunVisibility();
        color += sunColor * (specCore * 1.3 + specSoft) * shadow * WATER_GLINT_STRENGTH * glintDay;
        color += sunColor * sparkle * 1.3 * shadow * WATER_GLINT_STRENGTH * glintDay;

        // Dancing seabed caustics: a net-like pattern of light brightest
        // in shallow, sunlit water, fading out with depth (light has
        // scattered too much to focus into sharp lines by the time it
        // reaches deep water) and fading with shadow (no direct light
        // reaching this patch at all).
        float caustics = causticPattern(worldXZ, frameTimeCounter);
        caustics *= shadow * (1.0 - clamp(depthFactor * 1.8, 0.0, 1.0));
        color += sunColor * caustics * CAUSTICS_STRENGTH * 0.5 * glintDay;
    } else if (isWater > 0.5) {
        vec3 wallTint = mix(vec3(0.09, 0.30, 0.36), vColor.rgb * 0.4, 0.65);
        // BUGFIX: multiplying by 3.0 here amplified whatever ambient light reached
        // the water walls by 3x, which at night meant faint moon-ambient became
        // visible bright-teal glowing edges at the water surface boundary.
        // Scale the amplifier by day factor so walls are subtly dark at night.
        float wallBrightness = mix(1.2, 2.0, getDayFactor());
        color = mix(color * wallTint * wallBrightness, color, 0.35);
        outAlpha = clamp(outAlpha + 0.25, 0.0, 0.82);
    } else {
        // Glass (clear or stained) - previously just flat lit albedo
        // with no refraction, reflection, or glare at all, unlike every
        // other translucent surface in this pack.
        bool isClearGlass = (blockId >= 10102.0 && blockId < 10103.0);

        // REVERTED: glass used to sample colortex3 for both refraction
        // (a wobble on what's visible through the pane) and SSR
        // reflection (a real screen-space raytraced mirror). Both went
        // through multiple rounds of targeted fixes (UV scale, a
        // sky-read guard, sanitizeColor) and the mosaic corruption kept
        // coming back - glass hits the colortex3-at-sky case far more
        // than water ever did, since a window or greenhouse roof very
        // commonly has open sky directly behind it. Rather than attempt
        // a fourth patch on the same mechanism, pulled both out
        // entirely - same call as water's refraction removal. `color`
        // below is just this glass pixel's own lit albedo, and the
        // reflection is a fixed sky/sun tint with no screen-space
        // sampling at all, so neither can reproduce this bug regardless
        // of its exact root cause.
        vec3 viewDirToCam = normalize(mat3(gbufferModelView) * normalize(-worldPos));
        float NdotV = clamp(dot(normal, viewDirToCam), 0.0, 1.0);
        float fresnel = pow(1.0 - NdotV, 5.0);
        fresnel = clamp(fresnel * 0.85 + 0.05, 0.0, 0.9);

        vec3 skyRefl = mix(getAmbientSkyColor(), sunColor, 0.32);

        #if WATER_REFLECTION_MODE != 3
            color = mix(color, skyRefl, fresnel);
            outAlpha = mix(outAlpha, 0.9, fresnel * 0.4);
        #endif

        // Sun glare: a tight, bright glint on CLEAR glass only when it's
        // angled to catch the sun's reflection straight-on - stained
        // glass skips this (its own colored transmission through
        // computeShadowTint already reads as "lit up", a second white
        // glare on top of colored panes just muddies the color instead
        // of reading as glare).
        if (isClearGlass && GLASS_GLARE_STRENGTH > 0.0) {
            vec3 reflectDir = reflect(-viewLightDir, normal);
            float glareDot = max(dot(reflectDir, viewDirToCam), 0.0);
            float glareCore = pow(glareDot, 500.0) * 2.2;
            float glareStreak = pow(glareDot, 60.0) * 0.25;
            color += sunColor * (glareCore + glareStreak) * shadow * GLASS_GLARE_STRENGTH;
        }
    }

    float viewDist = length((gbufferModelView * vec4(worldPos, 1.0)).xyz);
    color = applyFog(color, fogColor, viewDist, worldPos.y, cameraPosition.y);

    gl_FragData[0] = vec4(sanitizeColor(color), outAlpha);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 0.0);
}
