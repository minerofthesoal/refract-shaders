#version 120
/* Refract Shaders - composite1.fsh
   Bright-pass extraction for bloom. The result is written into
   colortex2, which has mipmaps enabled (see const below) so composite2
   can cheaply sample several blur radii via textureLod. */

#include "/lib/common.glsl"

uniform sampler2D colortex0;

varying vec2 texcoord;

const bool colortex2MipmapEnabled = true;
// Explicit, rather than relying on Iris's default - guarantees smooth
// bilinear/trilinear sampling across colortex2's mip chain. Cheap
// insurance against the exact kind of blocky-mip artifact the tent
// filter in composite2.fsh's sampleBloomMip is also guarding against.
const bool colortex2Nearest = false;

/* RENDERTARGETS: 2 */

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float threshold = BLOOM_THRESHOLD;
    float knee = 0.20;

    float soft = clamp(luma - threshold + knee, 0.0, 2.0 * knee);
    soft = (soft * soft) / (4.0 * knee + 0.0001);
    float contribution = max(luma - threshold, soft) / max(luma, 0.0001);

    vec3 bright = color * clamp(contribution, 0.0, 1.0);

    gl_FragData[0] = vec4(bright, 1.0);
}
