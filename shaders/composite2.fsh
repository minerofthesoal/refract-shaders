#version 120
#extension GL_ARB_shader_texture_lod : enable
/* Refract Shaders - composite2.fsh
   Combines several mip levels of the bright-pass buffer (colortex2) to
   approximate a soft multi-radius gaussian bloom, then adds it back
   onto the HDR scene color in colortex0. */

#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex2;

varying vec2 texcoord;

/* RENDERTARGETS: 0 */

vec3 sampleBloomMip(sampler2D tex, vec2 uv, float lod) {
    // BUGFIX: sampling a single texel at a coarse mip level directly
    // can show that mip's OWN texel grid as a visible hard-edged
    // rectangle - a strong, compact HDR source (the sun) sitting
    // mostly within one or two texels of a heavily-downsampled mip
    // (mip 5 is a 32x downsample: each texel there already averages a
    // 32x32 block of the original screen) reads as a flat, boxy glow
    // matching that texel's own square footprint once magnified back
    // up, rather than a smooth radial falloff. This is a well-known
    // failure mode of simple "sample the raw mip chain directly" bloom
    // - the standard fix is a small tent/box filter of bilinear-
    // sampled taps around the same point at the same mip level, which
    // forces interpolation ACROSS neighboring texels of that mip
    // instead of ever reading one of them flat.
    vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
    vec3 sum = vec3(0.0);
    sum += texture2DLod(tex, uv + vec2(-texel.x, -texel.y), lod).rgb;
    sum += texture2DLod(tex, uv + vec2( texel.x, -texel.y), lod).rgb;
    sum += texture2DLod(tex, uv + vec2(-texel.x,  texel.y), lod).rgb;
    sum += texture2DLod(tex, uv + vec2( texel.x,  texel.y), lod).rgb;
    sum += texture2DLod(tex, uv, lod).rgb * 4.0;
    return sum * 0.125; // weighted average, center-heavy tent
}

void main() {
    vec3 sceneColor = texture2D(colortex0, texcoord).rgb;

    // BUGFIX: the old weighting (0.32/0.26/0.20/0.14/0.08) put nearly a
    // third of the total bloom energy into mip 4-5, which sample a 16x
    // and 32x downsampled version of the bright-pass buffer - each texel
    // there already represents an average over a huge screen area. For a
    // strong, compact source (the sun/horizon glow at dusk, especially
    // seen through many small gaps in tree canopy) that meant a large
    // fraction of its brightness got smeared across a correspondingly
    // huge area of screen instead of staying a tight glow near the
    // source - part of what read as the sky "blowing out" over a big
    // chunk of the frame. Shifting weight toward the tighter mips keeps
    // bright highlights (water glints, lava, glowstone) reading as punchy
    // and local; the widest mip is kept at a small non-zero weight so
    // very large/bright skies still get *some* soft ambient bloom, just
    // not enough to dominate. Weights still sum to 1.0.
    vec3 bloom = vec3(0.0);
    bloom += sampleBloomMip(colortex2, texcoord, 1.0) * 0.42;
    bloom += sampleBloomMip(colortex2, texcoord, 2.0) * 0.28;
    bloom += sampleBloomMip(colortex2, texcoord, 3.0) * 0.16;
    bloom += sampleBloomMip(colortex2, texcoord, 4.0) * 0.09;
    bloom += sampleBloomMip(colortex2, texcoord, 5.0) * 0.05;

    vec3 color = sceneColor + bloom * BLOOM_STRENGTH;

    gl_FragData[0] = vec4(color, 1.0);
}
