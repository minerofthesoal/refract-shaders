#version 120
/* Refract Shaders - gbuffers_skybasic.vsh - sky gradient, stars, void plane */

#include "/lib/common.glsl"

varying vec3 viewDir;
varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    vColor = gl_Color;
    vec4 viewSpace = gl_ModelViewMatrix * gl_Vertex;
    viewDir = normalize((gbufferModelViewInverse * vec4(viewSpace.xyz, 0.0)).xyz);
}
