#version 120
/* Refract Shaders - composite.vsh - fullscreen pass-through */

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
