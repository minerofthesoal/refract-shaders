#version 120
/* Refract Shaders - gbuffers_basic.fsh */

#include "/lib/common.glsl"

varying vec4 vColor;

/* RENDERTARGETS: 0,1 */

void main() {
    gl_FragData[0] = vColor;
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 0.0);
}
