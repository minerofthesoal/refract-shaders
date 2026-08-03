#version 120
/* Refract Shaders - gbuffers_hand.fsh */

#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;

/* RENDERTARGETS: 0,1 */

void main() {
    vec4 albedo = texture2D(gtexture, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec3 normal = normalize(viewNormal);
    vec3 sunColor = getSunColor() * (0.6 + 0.55 * getSunVisibility());
    vec3 ambient = getAmbientSkyColor() * (0.35 + 0.65 * lmcoord.y);
    float NdotUp = max(dot(normal, vec3(0.0, 1.0, 0.0)), 0.0);
    vec3 blockGlow = vec3(1.0, 0.7, 0.42) * pow(lmcoord.x, 1.6) * 1.2;

    vec3 lighting = max(ambient + sunColor * 0.35 * NdotUp * lmcoord.y + blockGlow, vec3(0.05));
    lighting = softenHighlights(lighting);
    vec3 color = albedo.rgb * lighting;

    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 0.0);
}
