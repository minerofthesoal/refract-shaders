#version 120
/* Refract Shaders - gbuffers_hand.vsh - first-person held item/block */

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
}
