#version 120
/* Refract Shaders - gbuffers_textured.fsh */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;

/* RENDERTARGETS: 0,1 */

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.05) discard;

    vec3 light = texture2D(lightmap, lmcoord).rgb;
    vec3 ambient = getAmbientSkyColor();
    vec3 color = albedo.rgb * max(light + ambient * 0.15, vec3(0.06));

    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 0.0);
}
