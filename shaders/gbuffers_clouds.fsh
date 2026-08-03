#version 120
/* Refract Shaders - gbuffers_clouds.fsh
   Vanilla's flat cloud layer is fully replaced by the procedural
   Perlin-noise volumetric clouds raymarched in composite.fsh - so this
   pass now discards every fragment instead of drawing the old flat
   quads. Iris still runs the vanilla cloud geometry through this
   program (that's unavoidable - the game always builds the cloud
   mesh), but nothing from it reaches the screen. */

void main() {
    discard;
}
