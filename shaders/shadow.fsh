#version 120
/* Refract Shaders - shadow.fsh
   Per-pixel colored shadows: writes the ACTUAL sampled texture color
   at each shadow-casting fragment into shadowcolor0, so light coming
   through a stained-glass window or a leaf canopy picks up that exact
   pixel's color/alpha - not a flat per-block average. This is real
   per-texel data (sampled from the block's own texture, same as the
   main render), not a lookup table.

   Only genuinely translucent casters (leaves, glass, ice - tagged in
   block.properties) actually tint what they shadow. Solid opaque
   blocks (stone, wool, dirt...) write alpha 0 here, so a red wool
   block doesn't unrealistically dye the shadow it casts red - only
   material light can plausibly pass through gets to tint anything. */

#include "/lib/common.glsl"

uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 vColor;
varying float blockId;

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;

    // Fully transparent fragments (cutout foliage holes, etc.) should
    // not occlude light at all.
    if (albedo.a < 0.05) discard;

    bool isFoliage   = (blockId >= 10200.0 && blockId < 10300.0);
    bool isGlass     = (blockId >= 10102.0 && blockId < 10104.0);
    bool isIce       = (blockId >= 10101.0 && blockId < 10102.0);
    bool canTint     = isFoliage || isGlass || isIce;

    // Depth is still written for every caster (this alpha only controls
    // how much of THIS fragment's own sampled color bleeds into the
    // shadow tint later - it is not a depth/occlusion alpha).
    float tintAlpha = 0.0;
    if (isFoliage) {
        tintAlpha = albedo.a * 0.35;   // soft, semi-translucent canopy shadow
    } else if (isGlass) {
        tintAlpha = albedo.a * 0.6;    // clearly colored light through glass, without blowing out
    } else if (isIce) {
        tintAlpha = albedo.a * 0.2;    // faint cool tint through ice
    }
    tintAlpha *= COLORED_GLASS_STRENGTH;

    // gl_FragData[0] becomes shadowcolor0 - sampled by every lit
    // gbuffer pass to tint shadows with the real per-pixel caster color.
    gl_FragData[0] = vec4(albedo.rgb, tintAlpha);
}
