#version 120
/* Refract Shaders - gbuffers_skytextured.vsh - sun & moon disc */

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
}
