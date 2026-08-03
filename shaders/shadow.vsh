#version 120
/* Refract Shaders - shadow.vsh
   Renders the scene from the sun/moon's point of view into the shadow
   map. const shadowMapResolution/shadowDistance below configure Iris's
   shadow render target directly. */

#include "/lib/common.glsl"

const int   shadowMapResolution = SHADOW_RES;
const float shadowDistance      = SHADOW_DISTANCE;
const float shadowDistanceRenderMul = 1.0;
const float sunPathRotation = 0.0;

attribute vec4 mc_Entity;

varying vec2 texcoord;
varying vec4 vColor;
varying float blockId;

void main() {
    blockId = mc_Entity.x;

    gl_Position = ftransform();

    // Pull shadow geometry very slightly toward the light to reduce
    // peter-panning / acne on thin geometry like foliage and torches.
    gl_Position.z -= 0.0006 * sign(gl_Position.z);

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
}
