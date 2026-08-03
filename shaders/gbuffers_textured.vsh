#version 120
/* Refract Shaders - gbuffers_textured.vsh - particles, GUI-ish elements rendered in world */

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;
}
