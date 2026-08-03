#version 120
/* Refract Shaders - gbuffers_terrain.fsh */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldPos;
varying vec3 shadowClipPos;
varying float blockId;
varying float emissive;

/* RENDERTARGETS: 0,1,3 */

void main() {
    // Boost saturation on vanilla's own per-biome vertex color tint,
    // weighted inversely to how saturated it already is. Taiga (spruce)
    // grass in particular reads as dull/colorless because vanilla's own
    // taiga tint genuinely is a fairly desaturated green-gray by
    // design - passed straight through unmodified next to more vivid
    // biomes, it has almost no visual identity of its own. Biomes
    // vanilla already colors vividly (jungle, swamp) get little to no
    // change here since their vColorSat is already high; muted tints
    // (taiga, badlands grass, desert's near-white sand) get pushed
    // further from gray. This runs on every terrain fragment, but a
    // block with no real biome tint (vColor at or near white) has
    // vColorSat near 0, so satBoost sits at its 1.0 floor and this is a
    // no-op for it - stone, sand, and similar untinted blocks pass
    // through unchanged.
    float vColorLuma = dot(vColor.rgb, vec3(0.299, 0.587, 0.114));
    float vColorSat = length(vColor.rgb - vec3(vColorLuma));
    float satBoost = mix(1.45, 1.0, clamp(vColorSat * 4.0, 0.0, 1.0));
    vec3 biomeVColor = mix(vec3(vColorLuma), vColor.rgb, satBoost);

    vec4 albedo = texture2D(gtexture, texcoord) * vec4(biomeVColor, vColor.a);
    if (albedo.a < 0.1) discard;

    vec3 normal = normalize(viewNormal);

    // shadowLightPosition is supplied by Iris already in view space
    // (camera-relative and pre-rotated), so it's used directly here -
    // rotating it again by gbufferModelView would double-transform it
    // and make the lighting direction swing incorrectly with camera look.
    vec3 viewLightDir = normalize(shadowLightPosition);
    float NdotL = max(dot(normal, viewLightDir), 0.0);

    // --- Lightmap (block light + sky light) ------------------------
    // Read up front (was previously read after the shadow block) so
    // the sky-exposure check below can gate the whole shadow/tint
    // sampling step on it.
    float skyLight  = lmcoord.y;
    float blockLight = lmcoord.x;

    // --- Shadow ---------------------------------------------------
    // OPTIMIZATION: a fragment with zero sky light (skyLight == 0) is
    // fully enclosed - no sun/moon ray or sky-transmitted glass tint
    // can reach it regardless of what the shadow map says, since both
    // `ambient` and `direct` below are themselves multiplied by
    // skyLight and collapse to 0 either way. Skipping the PCF shadow
    // tap plus both shadowcolor0 tint samples (tight + wide-radius
    // bleed) here is a straight win in interior-heavy scenes with no
    // visible difference, since their result was always getting
    // multiplied away.
    float shadow = 0.0;
    vec3 shadowTint = vec3(1.0);
    if (skyLight > 0.001) {
        // Slope-scaled bias (see slopeScaledBias) instead of one fixed
        // constant - grazing-angle surfaces need more bias to avoid acne,
        // directly-lit surfaces need less to avoid peter-panning.
        shadow = sampleShadowPCF(shadowtex1, shadowClipPos, slopeScaledBias(NdotL));

        // Real canopy darkening (not just recoloring) under leaves - see
        // translucentCanopyOcclusion in common.glsl for why the existing
        // GLASS_SKYLIGHT_STRENGTH dimming further below barely touches
        // forests/jungles (it was tuned for glass panes, and leaves
        // deliberately write a much fainter tint alpha than glass does so
        // a single leaf block doesn't look opaque). This is independent
        // of that mechanism and reuses the exact same PCF kernel already
        // being spent on `shadow`, just against shadowtex0 instead of
        // shadowtex1. Applied before the distance fade below, against the
        // same raw (un-faded) `shadow` value the shadowtex0 sample is
        // itself relative to - fading one side but not the other would
        // read as a canopy far beyond the shadow map's own render
        // distance, right where `shadow` is being faded back to fully lit
        // and shadowtex0's sample no longer means anything comparable.
        shadow *= translucentCanopyOcclusion(shadowtex0, shadowClipPos, slopeScaledBias(NdotL), shadow);

        // Fade to fully-lit near the shadow map's outer edge instead of a
        // hard pop the instant a fragment steps outside it - see
        // shadowDistanceFadeFactor in common.glsl.
        shadow = mix(shadow, 1.0, shadowDistanceFadeFactor(worldPos));
        // Colored shadow tint from stained-glass / leaves above us.
        //
        // BUGFIX: this used to be gated behind `if (shadow < 0.999)`. `shadow`
        // is sampled against shadowtex1, which only contains OPAQUE casters -
        // glass/leaves/ice are translucent and never block shadowtex1, so
        // standing under stained glass always read shadow == 1.0 ("fully lit")
        // and the gate skipped the tint lookup entirely. That's why colored
        // light through glass never showed up. shadowcolor0 is empty (alpha
        // 0) anywhere nothing translucent is overhead, so computeShadowTint
        // safely returns vec3(1.0) (no tint) there - it's cheap and correct
        // to just always sample it instead of trying to pre-guess when it's
        // needed.
        // BUGFIX #2: comparing against shadowtex0 (ALL casters, opaque +
        // translucent) instead of just gating on `shadow`. A translucent
        // caster (glass/leaves/ice) is normally the closest thing to the sun
        // at its own shadow-map texel, so a naive "always sample" tint
        // lookup was tinting the glass WITH ITS OWN COLOR - a self-feedback
        // loop that blew it out to an oversaturated glow. Only a fragment
        // meaningfully further from the sun than the caster (a receiver,
        // like the floor underneath) should pick up the tint; the caster's
        // own surface should not.
        float casterDepth = texture2D(shadowtex0, shadowClipPos.xy).r;
        if (shadowClipPos.z - casterDepth > 0.0025) {
            // PCF-filtered instead of a single texel tap - see
            // sampleShadowTintPCF in common.glsl for why: an unfiltered
            // tap here reproduced the shadow map's own blocky/triangular
            // texel edges as a hard-edged patch of color on the ceiling/
            // floor below a stained-glass window instead of a soft glow.
            vec4 tint = sampleShadowTintPCF(shadowcolor0, shadowClipPos.xy);
            shadowTint = computeShadowTint(tint, worldPos);

            // Glass "skylight" shadow: real light passing through even
            // clear glass loses some intensity to reflection, and
            // stained glass blocks a real fraction of it outright
            // rather than just recoloring it - dims direct light a bit
            // under any translucent caster instead of passing 100% of
            // the sun's intensity straight through untouched, scaled by
            // how strongly tinted the caster's own shadowcolor sample
            // reads (a deeply saturated stained-glass pane dims more
            // than a faint hint of thin leaves).
            shadow *= mix(1.0, 0.45, GLASS_SKYLIGHT_STRENGTH * clamp(tint.a, 0.0, 1.0));
        } else if (GLASS_BLEED_STRENGTH > 0.0) {
            // Not directly under a caster, but a much wider sample of
            // the same shadowcolor buffer might still catch a nearby
            // stained-glass window just outside its own sharp shadow
            // silhouette - see sampleShadowTintBleed in common.glsl.
            vec4 bleed = sampleShadowTintBleedDynamic(shadowcolor0, shadowClipPos.xy);
            vec3 bleedTint = computeShadowTint(bleed, worldPos);
            shadowTint = mix(vec3(1.0), bleedTint, GLASS_BLEED_STRENGTH * 0.5);
        }
    }

    float sunVisibility = getSunVisibility();
    vec3 sunColor = getSunColor() * (0.6 + 0.55 * sunVisibility);

    // No baseline floor on ambient anymore: a fully enclosed area with
    // zero sky light (skyLight == 0) now genuinely gets zero ambient,
    // not a guaranteed quarter of the sky color regardless of how
    // enclosed it is. That's what "dark without a torch" actually
    // means - a sealed room should be exactly as dark at noon as it is
    // at midnight, since no outside light reaches it either way.
    //
    // BUGFIX: ambient (diffuse sky light) now picks up shadowTint too,
    // same as direct. It previously only tinted the direct sun term,
    // so a stained-glass window only visibly coloured its light patch
    // when direct sun was actually hitting it - under an overcast/
    // rainy sky (or just soft shade), ambient sky light dominates the
    // lighting under the glass instead, and that ambient term was
    // passing straight through untinted. The visible result was a
    // patch that read as the sky's own ambient color (blue-gray) even
    // under red stained glass, instead of red - the same overhead pane
    // physically tints ALL light passing through it, not just a direct
    // sunbeam.
    vec3 ambient = getAmbientSkyColor() * skyLight * mix(0.8, 1.0, shadow) * shadowTint;

    vec3 direct = sunColor * NdotL * shadow * shadowTint * skyLight * cloudShadowFactor(worldPos);

    // --- Dynamic emissive block lighting ---------------------------
    bool isLava = (blockId >= 10012.0 && blockId < 10013.0);

    // OPTIMIZATION: all of the vein/flicker/churn math below only ever
    // applies to lava, so it's computed inside `if (isLava)` now instead
    // of unconditionally for every terrain fragment in the world.
    vec3 emissiveGlow = vec3(0.0);
    vec3 lavaOverrideColor = vec3(0.0);
    if (isLava) {
        // Surface churn: offsets which texel of the lava texture gets
        // sampled by a slow, drifting warp instead of reading the
        // fragment at its exact mesh UV - this is what actually makes
        // the molten surface look like it's heaving/shifting, on top of
        // whatever vanilla's own animated lava texture frames already
        // do. Two octaves at different scales/speeds so it doesn't read
        // as one uniform wobble.
        // BUGFIX: this used to call hash13() directly on continuous
        // worldPos, not on a floored lattice point the way hash13 is
        // supposed to be used (see how perlinNoise3D/valueNoise3D call
        // it below - always on floor(p) + an integer offset). hash13
        // was only ever designed to look random when sampled at
        // discrete integer points; fed a smoothly-sweeping continuous
        // input instead, its first step (fract(p * 0.1031)) is
        // essentially a sawtooth wave with a ~9.7-unit period in each
        // axis, and two of those sawtooths (X and Z) combining is
        // exactly what produces a diagonal interference/moire pattern -
        // this was a different, more fundamental bug than the mip-bias
        // or coordinate-precision issues fixed earlier, and had been
        // sitting here the whole time since neither of those touched
        // this code path. valueNoise3D does the floor+interpolate
        // properly and gives smooth, alias-free variation instead.
        vec2 churn = vec2(
            valueNoise3D(vec3(worldPos.xz * 0.35, frameTimeCounter * 0.10)) - 0.5,
            valueNoise3D(vec3(worldPos.zx * 0.35 + 71.0, frameTimeCounter * 0.085)) - 0.5
        ) * 0.05;
        // BUGFIX: this used to be a plain texture2D(gtexture, texcoord +
        // churn) with automatic mip selection. churn's offset (up to
        // 0.05 in absolute atlas-UV) is easily wider than a single
        // tile in the atlas, and at the points where the noise driving
        // it has its steepest gradient, the resulting large screen-
        // space UV derivative made automatic LOD selection jump to a
        // coarser mip level - one that blends across neighboring atlas
        // tiles rather than staying within lava's own texture region.
        // That cross-tile bleed at a shifting, noise-driven offset is
        // what read as thin, colored ("rainbow") lines drifting across
        // the lava instead of a clean molten surface.
        // BUGFIX (round 10): the bias actually applied here (-1.5) was
        // weaker than what this comment always claimed (-4.0) - a
        // leftover mismatch from an earlier tuning pass that never got
        // carried into the code. -1.5 still lets automatic LOD selection
        // drift up a level or two exactly where churn's derivative is
        // steepest, which is what the residual faceted/cross-tile
        // shimmer in testing traced back to. Matching the bias to what
        // was always intended forces sampling back down near the base
        // mip regardless of derivative size, so it can only ever read
        // lava's own texture region.
        vec4 lavaAlbedo = texture2D(gtexture, texcoord + churn, -4.0) * vColor;

        vec2 lavaWorldXZ = worldPos.xz + cameraPosition.xz;

        // At grazing viewing angles across a large lava surface (a wide
        // lake stretching toward the horizon), a single screen pixel
        // can span many world units of lavaWorldXZ - sampling cloudFBM
        // at wildly different input points between adjacent pixels
        // aliases into a moire/interference pattern of its own, the
        // same way an un-mipmapped regular texture aliases into moire
        // at a distance. fwidth measures that per-pixel rate of change
        // directly, so fading each octave out as its own derivative
        // grows keeps the pattern clean up close while avoiding the
        // alias far away/at grazing angles.
        //
        // BUGFIX: this has to be measured BEFORE the mod() wrap below,
        // not after. mod() introduces a hard jump (from ~10000 back to
        // 0) at its wrap boundary - if two neighboring screen pixels
        // happen to straddle that boundary, fwidth on the wrapped value
        // would see a spurious ~10000 jump between them that has
        // nothing to do with viewing angle, feeding garbage into the
        // fade logic right at that seam. Measuring on the real,
        // continuous coordinate first avoids that entirely.
        float lavaDeriv = length(fwidth(lavaWorldXZ));
        float coarseFade = 1.0 - smoothstep(4.0, 14.0, lavaDeriv);
        float fineFade = 1.0 - smoothstep(1.5, 6.0, lavaDeriv);

        // BUGFIX (the real root cause of the ring/interference pattern):
        // this pattern showed up just as strongly on a close, direct
        // view of the lava as at a distance, which the derivative-based
        // fade above can't explain on its own - that fix targets
        // viewing-angle aliasing, not this. The actual cause is float
        // precision: lavaWorldXZ is raw absolute world coordinates, and
        // far from spawn (a debug overlay from testing showed
        // coordinates in the thousands) those get large enough that the
        // hash-based noise inside cloudFBM starts losing meaningful
        // fractional precision, which for a hash function shows up as
        // chaotic, non-smooth output rather than a graceful quality
        // drop. Wrapping into a bounded range before feeding the noise
        // fixes this at the source - it's still deterministic for any
        // given world position (so the pattern doesn't shift as the
        // camera moves), and the resulting seam at the 10000-unit
        // wrap boundary (cloudFBM isn't actually periodic there) is
        // vanishingly unlikely to matter in practice since it'd require
        // a lava lake to span a literal multiple of 10000 blocks.
        lavaWorldXZ = mod(lavaWorldXZ, 10000.0);

        float hotspot = mix(0.5, cloudFBM(vec3(lavaWorldXZ * 0.045, frameTimeCounter * 0.035)), coarseFade);
        hotspot += (cloudFBM(vec3(lavaWorldXZ * 0.16 + 91.0, frameTimeCounter * 0.09)) - 0.5) * 0.4 * fineFade;
        // Extra high-frequency crackle on top of the two broad octaves
        // above - without this, a small pool (a single source block plus
        // a tile or two of flow) barely samples any variation across the
        // broad-scale noise and reads as one smooth gradient blob instead
        // of a churning, cracked molten surface. Kept deliberately faint
        // (0.06, down from an initial 0.12 that read as too busy once
        // combined with the other fixes above) and only where fineFade
        // is already high (close/direct views).
        hotspot += (cloudFBM(vec3(lavaWorldXZ * 0.55 - 37.0, frameTimeCounter * 0.14)) - 0.5) * 0.06 * fineFade;
        // Modestly wider transition band than the original 0.42-0.62 -
        // that tighter band could read as a hard, slightly banded edge
        // between "crust" and "vein" right where two similar hotspot
        // values sat close together. Pulled back in from an initial
        // 0.36-0.68 (too soft/busy-looking combined with the extra
        // octave above) to a smaller widening.
        float lavaVein = smoothstep(0.40, 0.64, hotspot);

        // Vanilla's own animated texture still contributes fine per-
        // texel detail/embers on top, just as a subtle modulation now
        // instead of being the primary color driver.
        float lavaLuma = dot(lavaAlbedo.rgb, vec3(0.299, 0.587, 0.114));

        // Fast per-pixel hotspot flicker (existing behavior) layered
        // under a much slower, large-scale "breathing" pulse so whole
        // patches of the lake dim and brighten over several seconds,
        // like a real lava lake's crust cracking and resealing, rather
        // than every pixel flickering independently and uniformly.
        // Same bug as churn above - hash13 called directly on
        // continuous position instead of a floored lattice point.
        // valueNoise3D gives the same "fast per-pixel flicker" intent
        // without the periodic sawtooth structure showing through as a
        // visible stripe pattern.
        float lavaFlicker = 0.85 + 0.30 * valueNoise3D(vec3(worldPos.xz * 0.6, frameTimeCounter * 0.85))
                                  + 0.10 * valueNoise3D(vec3(worldPos.zx * 2.3, frameTimeCounter * 2.4));
        float breathe = 0.85 + 0.15 * sin(frameTimeCounter * 0.35 + hash12(floor(worldPos.xz * 0.5)) * 6.28);
        lavaFlicker *= breathe;

        // Brighter, more saturated at both ends than before - reference
        // shots show lava reading as a genuinely strong, vivid light
        // source (blooming hard against dark surroundings), not a muted
        // orange rock texture. Crust is a rich, still-clearly-glowing
        // dark red rather than near-black; vein is pushed further into
        // HDR so it actually blooms.
        vec3 crustColor = vec3(0.65, 0.16, 0.02);
        vec3 veinColor  = vec3(3.4, 2.0, 0.35);
        vec3 hotColor = mix(crustColor, veinColor, lavaVein);
        hotColor *= mix(0.88, 1.18, lavaLuma);

        // Fresnel glow rim: grazing-angle view of the lava surface (e.g.
        // looking across a lava lake rather than straight down into it)
        // picks up extra warm glow along its silhouette, the way a real
        // incandescent surface's apparent brightness increases toward
        // grazing angles.
        vec3 viewPosLava = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
        vec3 viewDirLava = normalize(-viewPosLava);
        float lavaFresnel = pow(1.0 - clamp(dot(normal, viewDirLava), 0.0, 1.0), 3.0);

        // BUGFIX: this used to multiply lavaAlbedo.rgb (the raw, full-
        // color texture sample) directly into the final color here, on
        // top of the luma-based modulation already folded into hotColor
        // two lines up (hotColor *= mix(0.88, 1.18, lavaLuma)) - the
        // comment above always described this as "a subtle modulation",
        // but multiplying in the full RGB a second time meant every
        // texel-level swirl in vanilla's own animated lava texture was
        // baked directly into the output color, not just its brightness.
        // That was always slightly there, but forcing full mip-0
        // sharpness (the -4.0 bias fix above) removed the automatic
        // blurring that had been hiding it, which is what turned it into
        // an obvious wrinkled/crumpled-foil texture instead of a clean
        // molten surface. Dropping the redundant RGB multiply and
        // keeping only the luma-driven brightness modulation (the
        // procedural hotspot/vein pattern above stays the actual color
        // driver, as intended) fixes this without giving up the sharper,
        // bleed-free texture sampling from the bias fix.
        lavaOverrideColor = hotColor * lavaFlicker * (1.0 + lavaFresnel * 0.9);
        emissiveGlow = hotColor * (1.4 + lavaVein * 2.2) * lavaFlicker;
    } else if (emissive > 0.5) {
        vec3 warmGlow = vec3(1.0, 0.62, 0.28);
        emissiveGlow = warmGlow * 1.6;
    }
    // Held-light / nearby block light contributes warm glow too.
    vec3 blockGlow = vec3(1.0, 0.7, 0.42) * pow(blockLight, 1.6) * 1.35;

    vec3 lighting = ambient + direct + blockGlow + emissiveGlow;
    lighting = softenHighlights(lighting);
#if TRUE_BLACK_NIGHTS == 1
    // OLED mode: no artificial floor. Fully unlit ground (no sky light,
    // no block light, no direct sun) goes to true black.
    lighting = max(lighting, vec3(0.0));
#else
    lighting = max(lighting, vec3(0.035)); // never fully black
#endif

    vec3 color = albedo.rgb * lighting;
    // A second softening pass here (not just on lighting above) catches
    // high-albedo materials specifically - sand reflects roughly 85-90%
    // of incoming light, so even already-softened direct sun can still
    // multiply back up into overexposed territory once albedo is
    // applied, which is what was reading as deserts looking blown-out
    // compared to darker-albedo biomes under the same light.
    color = softenHighlights(color);

    // Emissive blocks should also self-illuminate their own albedo,
    // independent of incoming light (so lava/glowstone never look dark).
    if (isLava) {
        // Full self-lit override rather than a blend with the (dark,
        // unlit-looking) regular shading above it - lava should read as
        // an actual light source, not a slightly-brightened dark rock
        // texture.
        color = lavaOverrideColor;
    } else if (emissive > 0.5) {
        color = mix(color, albedo.rgb * vec3(1.3, 1.0, 0.75), 0.55);
    }

    // --- New feature: foliage backlight (subsurface-style glow) -----
    // Thin leaves/grass lit from behind should visibly glow - sunlight
    // scattering through a thin leaf is a large part of what makes real
    // forest canopy read as alive rather than a flat, uniformly front-lit
    // green wall. Approximated the usual cheap way (no real subsurface
    // transport): brighten when the surface faces AWAY from the sun but
    // the viewer is looking roughly back toward it, so the "far", normally
    // shadowed side of a leaf reads as translucently lit instead of dark.
    // Gated on `shadow` (this pack's own PCF result) so it only kicks in
    // when the sun is actually unoccluded from this position - a leaf
    // deep in a tree's own shadow shouldn't glow just because the ray
    // geometry lines up.
    bool isFoliageBlock = (blockId >= 10200.0 && blockId < 10300.0);
    if (isFoliageBlock && FOLIAGE_BACKLIGHT_STRENGTH > 0.0 && skyLight > 0.05) {
        vec3 viewPosFoliage = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
        vec3 viewDirFoliage = normalize(-viewPosFoliage);
        float facingAway = clamp(dot(-normal, viewLightDir), 0.0, 1.0);
        float towardSun = pow(clamp(dot(viewDirFoliage, -viewLightDir), 0.0, 1.0), 3.0);
        float backlight = facingAway * towardSun * shadow * skyLight;
        color += albedo.rgb * getSunColor() * backlight * FOLIAGE_BACKLIGHT_STRENGTH * 0.7;
    }

    // --- New feature: snow/ice sparkle -------------------------------
    // A sparse field of tiny, rapidly-cycling glints across snow/ice,
    // gated by a narrow half-vector specular lobe so each one only lights
    // up from a narrow range of view/sun angles - reads as light catching
    // individual ice crystal facets as the camera moves, rather than a
    // uniform shine across the whole surface.
    bool isSnowBlock = (blockId >= 10104.0 && blockId < 10105.0);
    if (isSnowBlock && SNOW_SPARKLE_STRENGTH > 0.0 && skyLight > 0.3) {
        vec3 viewPosSnow = (gbufferModelView * vec4(worldPos, 1.0)).xyz;
        vec3 viewDirSnow = normalize(-viewPosSnow);
        vec3 halfDir = normalize(viewLightDir + viewDirSnow);
        // Absolute world position (not camera-relative worldPos alone),
        // same reasoning as lavaWorldXZ above - otherwise the sparkle
        // cells would visibly drift/swim as the camera moves.
        vec3 sparkleWorld = mod(worldPos + cameraPosition, 10000.0);
        float glintSeed = hash13(floor(sparkleWorld * 9.0));
        float glintPhase = fract(glintSeed + frameTimeCounter * 0.6);
        float glintPulse = step(0.985, glintPhase);
        float glintLobe = pow(clamp(dot(normal, halfDir), 0.0, 1.0), 40.0);
        color += vec3(1.0, 1.0, 1.05) * glintPulse * glintLobe * shadow * skyLight * SNOW_SPARKLE_STRENGTH * 3.0;
    }

    // Cheap distance fog applied per-fragment for forward-shaded geometry.
    float viewDist = length((gbufferModelView * vec4(worldPos, 1.0)).xyz);
    color = applyFog(color, fogColor, viewDist, worldPos.y, cameraPosition.y);

    gl_FragData[0] = vec4(sanitizeColor(color), albedo.a);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, emissive);
    // Opaque-scene copy for water's SSR (see colortex3 note in
    // shaders.properties) - deliberately a separate buffer from
    // colortex0 so gbuffers_water can read it without also being one
    // of its writers in the same pass. Alpha here was previously
    // always a hardcoded 1.0 (unused - gbuffers_water only ever reads
    // .rgb from this buffer); now carries this fragment's own sky
    // light instead, so composite.fsh's rain-puddle pass can tell
    // which ground is actually exposed to the sky versus sheltered
    // under a roof without needing its own extra render target.
    gl_FragData[2] = vec4(sanitizeColor(color), skyLight);
}
