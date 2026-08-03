#version 120
/* Refract Shaders - gbuffers_water.vsh
   Handles translucent geometry: water, ice, stained glass, etc. */

#include "/lib/common.glsl"

attribute vec4 mc_Entity;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewNormal;
varying vec3 worldNormal;
varying vec3 worldPos;
varying vec3 shadowClipPos;
varying float blockId;
varying float isWater;

void main() {
    blockId = mc_Entity.x;
    // BUGFIX: this was `< 10102.0`, which covers block.10100 (water)
    // AND block.10101 (ice) - ice was never supposed to be included.
    // Ice was getting the full water treatment below: wave vertex
    // displacement included. Water's displacement only holds together
    // because every water vertex sharing an (x,z) computes the same
    // offset - but ice is placed as isolated single blocks, not a
    // contiguous body, so its edges border ordinary non-displaced
    // terrain with no matching offset to meet. That mismatch is exactly
    // what tore a sharp, faceted gap open at an ice block's edges -
    // the "floating diamond" artifact. Narrowed to just 10100 so ice
    // now correctly falls through to the glass branch in
    // gbuffers_water.fsh instead (flat, undisplaced, same as any other
    // translucent block).
    isWater = (blockId >= 10100.0 && blockId < 10101.0) ? 1.0 : 0.0;

    vec4 pos = gl_Vertex;

    // Vertex-level bobbing depends only on worldXZ, never on which
    // face/normal the vertex belongs to, so it's applied to every water
    // vertex (top face AND the vertical skirt faces around shorelines /
    // depth changes) uniformly - two vertices sharing an (x,z) always
    // compute the identical offset, so the mesh can't tear open.
    if (isWater > 0.5) {
        vec4 worldP = gbufferModelViewInverse * (gl_ModelViewMatrix * pos);
        worldP.xyz += cameraPosition;
        pos.y += waterHeightVertex(worldP.xz, frameTimeCounter);
    }

    vec4 viewSpace = gl_ModelViewMatrix * pos;
    gl_Position = gl_ProjectionMatrix * viewSpace;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    // World-space normal, independent of camera orientation - used to
    // decide whether this is a top-facing water surface regardless of
    // which way the camera is looking (see the matching note in
    // gbuffers_water.fsh).
    worldNormal = normalize((gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz);

    vec4 worldSpace = gbufferModelViewInverse * viewSpace;
    worldPos = worldSpace.xyz;

    shadowClipPos = worldToShadowClip(worldPos);
}
