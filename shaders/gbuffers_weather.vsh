#version 120
/* Refract Shaders - gbuffers_weather.vsh - rain & snow particles */

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec4 vColor;
varying float vertDist;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor   = gl_Color;

    vec4 viewSpace = gl_ModelViewMatrix * gl_Vertex;
    vertDist = length(viewSpace.xyz);
}
