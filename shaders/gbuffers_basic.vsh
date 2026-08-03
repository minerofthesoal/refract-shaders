#version 120
/* Refract Shaders - gbuffers_basic.vsh - block selection outline, debug lines, beacon beams */

#include "/lib/common.glsl"

varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    vColor = gl_Color;
}
