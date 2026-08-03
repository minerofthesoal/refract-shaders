#version 120
/* Refract Shaders - gbuffers_clouds.vsh */

#include "/lib/common.glsl"

varying vec4 vColor;
varying vec3 worldPos;

void main() {
    gl_Position = ftransform();
    vColor = gl_Color;
    vec4 viewSpace = gl_ModelViewMatrix * gl_Vertex;
    worldPos = (gbufferModelViewInverse * viewSpace).xyz;
}
