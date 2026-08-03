#version 120
/* Refract Shaders - gbuffers_entities.vsh */

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldPos;
varying vec3 shadowClipPos;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewSpace = gl_ModelViewMatrix * gl_Vertex;
    vec4 worldSpace = gbufferModelViewInverse * viewSpace;
    worldPos = worldSpace.xyz;

    shadowClipPos = worldToShadowClip(worldPos);
}
