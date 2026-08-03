#version 120
/* Refract Shaders - gbuffers_weather.fsh - rain & snow particles

   Vanilla's own tiling rain texture, rendered untouched, reads as a
   wall of hard, fully-saturated blue bars with no sense of depth or
   atmosphere - exactly what showed up in testing. This softens it:
   quieter base opacity, a fade toward transparent with distance so the
   far edge of the rain grid dissolves into haze instead of hard-
   cutting off at the draw radius, and a per-column brightness jitter
   so it doesn't read as one uniform, mechanically repeating sheet. */

#include "/lib/common.glsl"

uniform sampler2D gtexture;

varying vec2 texcoord;
varying vec4 vColor;
varying float vertDist;

/* RENDERTARGETS: 0,1 */

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.05) discard;

    vec3 ambient = getAmbientSkyColor();
    albedo.rgb *= max(ambient * 1.15, vec3(0.18));

    // Per-column brightness variation - without this every streak in
    // the tiling texture is identically lit, which is exactly what
    // makes it read as a mechanical overlay instead of individual
    // falling drops.
    float jitter = hash12(floor(texcoord * vec2(4.0, 1.0)));
    albedo.rgb *= mix(0.82, 1.06, jitter);

    // Softer base opacity than vanilla's own alpha (the raw texture at
    // a flat 0.55-0.85 multiplier is what produced the hard opaque blue
    // bars), fading further with distance so the far edge of the rain
    // grid dissolves into the fog/haze instead of hard-cutting off.
    float distFade = 1.0 - smoothstep(20.0, 56.0, vertDist);
    albedo.a *= mix(0.22, 0.42, rainStrength) * distFade;

    gl_FragData[0] = vec4(albedo.rgb, albedo.a);
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 0.0);
}
