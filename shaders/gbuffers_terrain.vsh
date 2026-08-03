#version 120
/* Refract Shaders - gbuffers_terrain.vsh
   Handles all opaque/cutout world terrain: solid blocks, foliage, etc. */

#include "/lib/common.glsl"

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldPos;       // camera-relative world position
varying vec3 shadowClipPos;
varying float blockId;
varying float emissive;

void main() {
    blockId = mc_Entity.x;
    emissive = (blockId >= 10000.0 && blockId < 10100.0) ? 1.0 : 0.0;
    float isFoliage = (blockId >= 10200.0 && blockId < 10300.0) ? 1.0 : 0.0;

    vec4 pos = gl_Vertex;

    // Subtle wind sway for foliage / leaves / kelp / seagrass.
    if (isFoliage > 0.5) {
        vec4 worldP = gbufferModelViewInverse * (gl_ModelViewMatrix * pos);
        worldP.xyz += cameraPosition;
        float sway = sin(frameTimeCounter * 1.6 + worldP.x * 0.6 + worldP.z * 0.6) * 0.045
                   + sin(frameTimeCounter * 2.3 + worldP.x * 1.3) * 0.02;
        // Only sway the upper part of the model (mc_midTexCoord trick keeps
        // the base anchored) — approximate using vertical position within block.
        float heightWeight = clamp(fract(pos.y) , 0.0, 1.0);
        if (blockId >= 10201.0 && blockId < 10203.0) heightWeight = 1.0; // leaves/kelp sway fully
        pos.x += sway * heightWeight;
        pos.z += sway * 0.8 * heightWeight;
    }

    vec4 viewSpace = gl_ModelViewMatrix * pos;
    gl_Position = gl_ProjectionMatrix * viewSpace;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 worldSpace = gbufferModelViewInverse * viewSpace;
    worldPos = worldSpace.xyz;

    shadowClipPos = worldToShadowClip(worldPos);
}
