#version 120
/* Refract Shaders - gbuffers_entities.fsh
   Mobs, players, item frames, etc. Includes dynamic lighting from a
   held glowing item (torch/glowstone/lantern in hand). */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform vec4 entityColor; // hurt-flash tint, (0,0,0,0) when not flashing

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldPos;
varying vec3 shadowClipPos;

/* RENDERTARGETS: 0,1,3 */

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec3 normal = normalize(viewNormal);

    // shadowLightPosition is already view-space (see note in
    // gbuffers_terrain.fsh) - do not rotate it again.
    vec3 viewLightDir = normalize(shadowLightPosition);
    float NdotL = max(dot(normal, viewLightDir), 0.0);

    // OPTIMIZATION: skip shadow/tint sampling entirely for entities with
    // no sky light (fully indoors) - see the matching note in
    // gbuffers_terrain.fsh. Both ambient and direct below are multiplied
    // by lmcoord.y anyway, so the result is thrown away regardless.
    float shadow = 0.0;
    vec3 shadowTint = vec3(1.0);
    if (lmcoord.y > 0.001) {
        shadow = sampleShadowPCF(shadowtex1, shadowClipPos, slopeScaledBias(NdotL));
        // Real canopy darkening under leaves (a deer standing under a
        // tree canopy should read dappled, not flat-lit) - see
        // translucentCanopyOcclusion in common.glsl. Applied before the
        // distance fade below so both PCF samples it compares are on the
        // same raw, un-faded footing.
        shadow *= translucentCanopyOcclusion(shadowtex0, shadowClipPos, slopeScaledBias(NdotL), shadow);
        shadow = mix(shadow, 1.0, shadowDistanceFadeFactor(worldPos));

        // BUGFIX (parity with gbuffers_terrain.fsh / gbuffers_water.fsh):
        // this used to gate on `shadow < 0.999`, but shadow only tests
        // against shadowtex1 (opaque casters only) - stained glass, leaves,
        // and ice are translucent and never register there, so an entity
        // standing under a stained-glass window always read shadow == 1.0
        // ("fully lit") and this gate skipped the tint lookup exactly where
        // it mattered. Comparing the caster depth from shadowtex0 (opaque +
        // translucent) instead correctly detects "something translucent is
        // between me and the sun" - the same fix already applied to
        // terrain/water, just never carried over to entities until now.
        float casterDepth = texture2D(shadowtex0, shadowClipPos.xy).r;
        if (shadowClipPos.z - casterDepth > 0.0025) {
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
    // No baseline floor - see the matching note in gbuffers_terrain.fsh.
    // An entity standing somewhere with zero sky light and zero block
    // light genuinely gets zero ambient now.
    //
    // BUGFIX: ambient now picks up shadowTint too - see the matching,
    // more detailed note in gbuffers_terrain.fsh. Without this, an
    // entity standing under red stained glass on an overcast/rainy day
    // (ambient sky light dominant, little/no direct sun getting
    // through) read as lit by the sky's own blue-gray ambient color
    // instead of the glass's red tint.
    vec3 ambient = getAmbientSkyColor() * lmcoord.y * mix(0.8, 1.0, shadow) * shadowTint;
    vec3 direct = sunColor * NdotL * shadow * shadowTint * lmcoord.y * cloudShadowFactor(worldPos);

    // Note: no separate "held item lights up nearby entities" term here.
    // vanilla's own lightmap (lmcoord.x) already correctly encodes
    // proximity-based block/held light falloff per-entity through the
    // game's lighting engine. A separate term using heldBlockLightValue
    // (a single global scalar, not distance-based) previously added the
    // same flat glow to EVERY entity on screen whenever the player held
    // a torch, regardless of actual distance - that's what was making
    // mobs look like they were glowing independently of proximity.
    vec3 blockGlow = vec3(1.0, 0.7, 0.42) * pow(lmcoord.x, 1.6) * 1.2;

#if TRUE_BLACK_NIGHTS == 1
    vec3 lighting = max(ambient + direct + blockGlow, vec3(0.0));
#else
    vec3 lighting = max(ambient + direct + blockGlow, vec3(0.04));
#endif
    lighting = softenHighlights(lighting);
    vec3 color = albedo.rgb * lighting;

    color = mix(color, entityColor.rgb, entityColor.a * 0.6);

    float viewDist = length((gbufferModelView * vec4(worldPos, 1.0)).xyz);
    color = applyFog(color, fogColor, viewDist, worldPos.y, cameraPosition.y);

    gl_FragData[0] = vec4(sanitizeColor(color), albedo.a);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 0.0);
    // See the matching note in gbuffers_terrain.fsh - alpha now carries
    // sky light instead of a hardcoded 1.0.
    gl_FragData[2] = vec4(sanitizeColor(color), lmcoord.y);
}
