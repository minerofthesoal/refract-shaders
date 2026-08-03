#version 120
/* Refract Shaders - gbuffers_skytextured.fsh
   Renders the sun and moon quads. Iris/OptiFine draw these through the
   SAME program, but expose which one is currently active via the
   `renderStage` uniform + MC_RENDER_STAGE_* macros, so we use that
   directly instead of guessing from texture color (the old approach
   misfired on anti-aliased texture edges and produced a blocky, wrongly
   -tinted disc). */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform int renderStage;

varying vec2 texcoord;
varying vec4 vColor;

/* RENDERTARGETS: 0,1 */

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.05) discard;

    bool isSun = (renderStage == MC_RENDER_STAGE_SUN);

    vec3 sunTint  = getSunColor() * 0.95;
    vec3 moonTint = vec3(0.55, 0.6, 0.72);
    float intensity = isSun ? (0.7 + 0.35 * getSunVisibility()) : 0.45 * (1.0 - 0.5 * getSunVisibility());

    vec2 shapeUV = isSun ? texcoord : fract(texcoord * vec2(4.0, 2.0));
    float edgeDist = length(shapeUV - 0.5) * 2.0;

    if (isSun) {
        // Semi-realistic sun instead of a flat tinted copy of sun.png
        // (which is just a plain painted disc with no real detail).
        // Real stars are dimmer toward the limb than the center -
        // you're looking through more of the cooler, more diffuse
        // outer atmosphere at a grazing angle near the edge than you
        // are looking straight in at the center - and the surface
        // itself roils with slow-moving plasma rather than sitting
        // static. Both are cheap to fake and make a big difference in
        // how "alive" the sun reads instead of looking like a painted-
        // on sticker.
        // BUGFIX: corona used to reach all the way to edgeDist 1.0 - the
        // quad's own corners/edge. Even at very low opacity there, that
        // thin band around the full quad boundary was bright enough
        // (this is an HDR sun color, headed straight into bloom) for
        // composite2.fsh's bloom pass to amplify it into a visible
        // glowing square/quad outline matching the underlying geometry's
        // own silhouette - a hard-edged trapezoid rather than a soft
        // round glow. Pulled the falloff in well short of the quad's
        // edge so there's no full-opacity boundary left for bloom to
        // pick out.
        float disc = 1.0 - smoothstep(0.52, 0.60, edgeDist);
        float corona = (1.0 - smoothstep(0.30, 0.68, edgeDist)) * 0.45;
        float shapeMask = max(disc, corona);
        if (shapeMask < 0.02) discard;

        float limbDarken = mix(1.0, 0.45, smoothstep(0.0, 0.6, edgeDist));

        // Two octaves of noise drifting at different rates/directions
        // so the disc reads as roiling plasma rather than a static
        // painted pattern or an obviously-scrolling single layer.
        vec2 turbUV = shapeUV * 5.0;
        float turb = valueNoise3D(vec3(turbUV + vec2(frameTimeCounter * 0.012, frameTimeCounter * 0.007), frameTimeCounter * 0.02)) * 0.6
                   + valueNoise3D(vec3(turbUV * 2.4 + 50.0 - vec2(frameTimeCounter * 0.02, 0.0), frameTimeCounter * 0.05)) * 0.4;
        float turbulence = mix(0.82, 1.22, turb);

        vec3 sunColorFinal = sunTint * intensity * mix(1.0, limbDarken * turbulence, disc);
        albedo.rgb = sunColorFinal * shapeMask;
        albedo.a = shapeMask;
    } else {
        // BUGFIX (round 13): the round-10 fix here assumed vanilla's
        // moon_phases.png alpha channel encodes each phase's real
        // crescent/gibbous cutout shape, and switched to trusting it
        // completely for shapeMask. It doesn't reliably do that - the
        // texture's alpha reads as effectively opaque across its whole
        // square tile, not just the visible disc, so shapeMask was
        // landing near 1.0 across the ENTIRE quad: a solid glowing
        // square rather than anything moon-shaped. At a grazing angle
        // and picked up by bloom, that's exactly what was showing up as
        // a large, hard-edged, diagonal box/plane in the sky.
        //
        // Back to a real geometric circular falloff to actually
        // constrain the shape, same technique the sun already uses
        // successfully (and which was never affected by this - it never
        // depended on texture alpha in the first place). The real
        // texture's COLOR (not alpha) still supplies the phase art and
        // surface detail within that boundary; phases now read through
        // shading/brightness pattern rather than a true geometric cutout,
        // which is a reasonable trade for not depending on texture data
        // that turned out not to behave the way it was assumed to.
        float disc = 1.0 - smoothstep(0.42, 0.50, edgeDist);
        float halo = (1.0 - smoothstep(0.32, 0.85, edgeDist)) * 0.35 * (1.0 - disc);
        float shapeMask = max(disc, halo);
        if (shapeMask < 0.02) discard;

        vec3 discColor = albedo.rgb * moonTint * intensity * 1.15;
        vec3 haloColor = moonTint * intensity * 0.55;
        albedo.rgb = mix(haloColor * halo, discColor, disc);
        albedo.a = shapeMask;
    }

    gl_FragData[0] = vec4(albedo.rgb, albedo.a);
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 1.0);
}
