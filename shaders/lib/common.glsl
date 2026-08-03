/*
    Refract Shaders - common.glsl
    Shared uniforms + utility functions included by (almost) every program.
    Include with:  #include "/lib/common.glsl"
    Include this BEFORE declaring file-specific samplers/varyings.
*/

#ifndef REFRACT_COMMON
#define REFRACT_COMMON

// ---------------------------------------------------------------------
// Standard Iris / OptiFine-spec uniforms (safe to declare even if a
// particular stage does not end up using all of them).
// ---------------------------------------------------------------------
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec3 fogColor;
uniform vec3 skyColor;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

uniform int   worldTime;
uniform int   worldDay;
uniform float frameTimeCounter;
uniform int   frameCounter;

uniform float rainStrength;
uniform float wetness;
uniform int   isEyeInWater;
uniform int   biome_category; // Iris-provided: current biome's category (CAT_JUNGLE, CAT_DESERT, etc. - see getBiomeGradeTint below)
uniform float temperature;    // Iris-provided: current biome's vanilla temperature value, roughly -0.7..2.0 (see getOceanTemperatureTint below)
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

uniform sampler2D noisetex;
const int noiseTextureResolution = 256;

// ---------------------------------------------------------------------
// Tunables - these surface automatically in the Iris shader options
// screen because of the bracket comment syntax.
// ---------------------------------------------------------------------
#define SHADOW_RES 2048          // Shadow map resolution [512 1024 2048 4096]
#define SHADOW_DISTANCE 160.0    // Shadow draw distance in blocks [48.0 80.0 96.0 128.0 160.0 224.0 320.0]
#define SOFT_SHADOWS 1           // PCF soft shadow filtering [0 1]
#define SHADOW_SOFTNESS 1.0      // Penumbra size - how much softer shadows get further from their caster [0.5 0.75 1.0 1.4 1.8 2.4]
#define COLORED_GLASS_STRENGTH 1.0 // Strength of the colored light cast through stained glass/leaves/ice [0.0 0.5 0.75 1.0 1.3 1.6]
#define GLASS_BLEED_STRENGTH 0.6 // How far colored light from glass spills onto nearby surfaces beyond its own sharp shadow silhouette, like real scattered light through a window [0.0 0.3 0.6 0.9 1.3]
#define GLASS_SKYLIGHT_STRENGTH 0.5 // How much glass/leaves/ice dim direct sunlight passing through them, not just recolor it - real stained glass blocks a real fraction of the light outright [0.0 0.3 0.5 0.75 1.0]
#define GLASS_BLEED_DYNAMIC_SPREAD 1 // Widen the colored-glass bleed radius near sunrise/sunset, like real low-angle light scattering further across a room [0 1]
#define GLASS_BLEED_DUSK_MULTIPLIER 2.2 // How much wider the bleed radius gets at peak dusk/dawn, when GLASS_BLEED_DYNAMIC_SPREAD is on [1.2 1.6 2.2 3.0 4.0]
#define FOLIAGE_SHADOW_STRENGTH 0.65 // How much a leaf canopy actually darkens (not just tints) direct/ambient light passing through it - low values leave forests reading flat/overlit despite a visible canopy overhead [0.0 0.3 0.5 0.65 0.8 1.0]
#define SSAO 1                   // Screen-space ambient occlusion - soft contact darkening in corners/crevices that a directional shadow map alone can't produce [0 1]
#define SSAO_STRENGTH 0.6        // AO effect intensity [0.0 0.3 0.45 0.6 0.8 1.0]
#define SSAO_SAMPLES 8           // AO sample count - higher is smoother but costs more per frame [4 8 12 16]
#define GODRAY_STRENGTH 0.55     // Volumetric god ray intensity [0.0 0.25 0.4 0.55 0.75 1.0]
#define GODRAY_STEPS 24          // God ray raymarch steps [4 6 8 12 16 24 32 48]
#define BLOOM_STRENGTH 0.65      // Bloom intensity [0.0 0.25 0.4 0.65 0.9 1.2]
#define BLOOM_THRESHOLD 1.15     // Luma threshold before bloom kicks in - higher = tighter, less "blobby" highlights (raised from 1.02 - the old value let a single bright water sparkle balloon into a big soft blob once blurred across bloom's mip chain) [0.85 1.0 1.15 1.3 1.5]
#define FOG_DENSITY 1.0          // Atmospheric fog density multiplier [0.0 0.5 1.0 1.5 2.0 3.0]
#define WATER_WAVE_HEIGHT 0.08   // Water wave amplitude in blocks [0.0 0.03 0.05 0.08 0.12 0.18]
#define WATER_REFLECTION_STRENGTH 1.0 // Mirror-reflection intensity at grazing angles [0.5 0.75 1.0 1.25 1.5]
#define WATER_CLARITY 1.0        // How far light penetrates before water reaches its full depth tint - higher stays clear longer, showing more seabed detail [0.5 0.75 1.0 1.3 1.6]
#define WATER_FOAM_STRENGTH 1.0  // Shoreline foam visibility [0.0 0.5 1.0 1.5 2.0]
#define WATER_GLINT_STRENGTH 0.7 // Sun/moon specular glint + sparkle intensity on water - lower this if the highlight blooms into one big soft glow instead of a tight sparkle [0.0 0.3 0.5 0.7 1.0 1.4]
#define CAUSTICS_STRENGTH 1.0    // Underwater caustic light patterns - both the dancing glints on a shallow seabed and the full-screen shimmer while swimming [0.0 0.5 1.0 1.5 2.0]
#define UNDERWATER_DISTORTION 1.0 // Screen-warp intensity while swimming [0.0 0.5 1.0 1.5 2.0]
#define UNDERWATER_FOG_DENSITY 1.0 // How quickly visibility falls off with distance while underwater - higher means murkier/shorter sight distance [0.0 0.5 1.0 1.5 2.0]
#define WET_REFLECTIONS 1        // Puddle-like screen-space reflections on flat, upward-facing ground while it's raining [0 1]
#define WET_REFLECTIONS_STRENGTH 0.85 // Intensity of wet-ground reflections [0.0 0.4 0.6 0.85 1.1 1.4]
#define CLOUD_SHADOW_STRENGTH 0.7 // How much clouds dim direct sunlight on the ground beneath them [0.0 0.3 0.5 0.7 0.9 1.0]
#define CHROMATIC_DISPERSION_STRENGTH 0.6 // Subtle prismatic fringing on water/reflections at grazing angles [0.0 0.3 0.6 1.0 1.5]
#define RAIN_RIPPLE_STRENGTH 1.0 // Animated concentric ripples on water surfaces while it's raining [0.0 0.5 1.0 1.5]
#define EXPOSURE 1.05            // Manual exposure [0.6 0.8 1.0 1.05 1.2 1.5 2.0]
#define SATURATION 1.18          // Final color grade saturation [0.7 0.85 1.0 1.08 1.18 1.3 1.4]
#define WARMTH 0.09              // Subtle warm/cool push in color grading [-0.2 -0.1 0.0 0.06 0.09 0.12 0.2]
#define VIGNETTE_STRENGTH 0.35   // Screen edge darkening [0.0 0.15 0.35 0.55 0.8]
#define NIGHT_DARKNESS 1         // Night ambient darkness level. 0=vanilla-ish, 1=dark, 2=very dark [0 1 2]
#define TRUE_BLACK_NIGHTS 0      // Opt-in extra darkness: pushes night ambient much lower and removes the enclosed-room light floor, so you genuinely need a light source to see. Off by default = normal moonlit night. [0 1]
#define NIGHT_BRIGHTNESS 1.0     // Extra night brightness multiplier, applied on top of NIGHT_DARKNESS - turn this up if night is too dark to see by even with NIGHT_DARKNESS/TRUE_BLACK_NIGHTS set low. [1.0 1.25 1.5 1.75 2.0 2.5 3.0]
#define CLOUD_STEPS 14           // Volumetric cloud raymarch steps [4 6 10 14 20 28]
#define CLOUD_COVERAGE 0.52      // Volumetric cloud coverage (lower = cloudier) [0.35 0.44 0.52 0.60 0.70]
#define CLOUD_OPACITY 0.85       // Volumetric cloud max opacity [0.4 0.6 0.85 1.0]
#define NIGHT_CLOUD_GLOW 1.0     // Moonlit rim-light + silver sheen on cloud undersides/edges at night, instead of clouds going nearly invisible after dusk [0.0 0.5 1.0 1.5 2.0]

// --- Water biome identity ---------------------------------------------
#define SWAMP_MURKINESS 1.0      // How opaque/dark swamp water reads compared to the pack's usual crystal-clear look - real swamp water is shallow, algae-thick, and doesn't show a clean sandy bottom [0.0 0.5 1.0 1.4 1.8]
#define OCEAN_TEMPERATURE_TINT 1.0 // Extra warm/tropical vs. icy/pale push on ocean water beyond vanilla's own per-biome water color, so warm/lukewarm/cold/frozen oceans read more distinctly [0.0 0.5 1.0 1.5 2.0]

// --- New atmosphere/life features --------------------------------------
#define FIREFLIES 1               // Drifting glowing insects over grass/foliage in forest, jungle, and swamp biomes at night [0 1]
#define FIREFLY_STRENGTH 1.0      // Firefly brightness/density [0.0 0.5 1.0 1.5 2.0]
#define AURORA 1                  // Aurora borealis ribbons in the night sky over cold biomes (taiga, icy, snowy peaks) [0 1]
#define AURORA_STRENGTH 0.8       // Aurora brightness [0.0 0.4 0.8 1.2 1.6]
#define SNOW_SPARKLE_STRENGTH 1.0 // Sun/moon glitter on snow and ice, like light catching ice crystals [0.0 0.5 1.0 1.5 2.0]
#define FOLIAGE_BACKLIGHT_STRENGTH 0.8 // Subsurface-style glow on thin leaves/grass when the sun is behind them, instead of foliage only ever reading as a flat-lit front face [0.0 0.4 0.8 1.2 1.6]
#define UNDERWATER_GODRAYS_STRENGTH 1.0 // Extra volumetric light shafts piercing down through the water surface, visible while swimming or looking up from underwater [0.0 0.5 1.0 1.5 2.0]
#define NIGHT_FOG_STRENGTH 0.7 // Light, noise-driven atmospheric haze near the ground at night, like real mist catching moonlight - independent of the regular distance fog [0.0 0.35 0.7 1.1 1.5]

// --- Voxy LoD mod compatibility -----------------------------------------
// Voxy (https://modrinth.com/mod/voxy) renders simplified terrain far past
// the normal `far` distance. This pack cannot see Voxy's own internal LoD
// state directly, but everything below keeps the existing distance-based
// atmosphere (fog, haze, and which effects even bother running) coherent
// out to the much larger visible range Voxy users actually run with,
// instead of assuming the world simply stops existing at vanilla `far`.
#define VOXY_COMPAT 1             // Fades out close-range-only effects (SSAO, contact shadows) smoothly past 96-128 blocks instead of a hard cutoff, and skips them past that entirely - meaningless detail at LoD-scale viewing distance, and otherwise wasted GPU time. Turn off to match this pack's exact pre-Voxy-support behavior. [0 1]

// --- Shadow mode -----------------------------------------------------
// 0 = shadow map only (default - the directional shadow map handles all
//     sun/moon shadows, same as always).
// 1 = adds a screen-space raymarched "contact shadow" pass on top of the
//     shadow map: a short-range ray is marched through the depth buffer
//     toward the sun for each pixel, catching small/close occluders
//     (corners, thin objects, block edges) that the shadow map's finite
//     texel resolution smooths over or misses entirely. This is the
//     same "sun-only" screen-space technique some other packs label
//     "raytraced shadows" - it's a real per-pixel ray march against the
//     depth buffer, just short-range (a few blocks) rather than a full
//     scene raytrace, since that's what a screen-space ray can actually
//     see.
// 2 = same technique, fewer march steps - cheaper, slightly less precise
//     contact-shadow edges.
#define SHADOW_MODE 0            // Screen-space sun contact shadows: off / on / on (lite) [0 1 2]
#define SSRT_SHADOW_STEPS 12     // Contact-shadow ray march steps (SHADOW_MODE 1) [6 8 12 16 24]
#define SSRT_SHADOW_STEPS_LITE 5 // Contact-shadow ray march steps (SHADOW_MODE 2) [3 4 5 6 8]
#define SSRT_SHADOW_RANGE 2.5    // How far the contact-shadow ray marches, in blocks [1.0 1.5 2.5 4.0 6.0]

// --- Water/glass reflection mode --------------------------------------
// 0 = default - today's full screen-space traced reflection (16-step
//     raymarch against the depth buffer). This is already a real
//     screen-space ray trace, it just wasn't labeled that way before.
// 1 = raytraced (lite) - the same technique with a shorter raymarch
//     (fewer steps), cheaper per-pixel at a small cost to hit accuracy
//     at glancing angles.
// 2 = no raytraced reflections - skips the raymarch entirely and falls
//     back to a flat sky/sun-color reflection (much cheaper, no chance
//     of screen-space misses/artifacts, but doesn't show the actual
//     reflected scene).
// 3 = none - reflections disabled outright; water/glass show their
//     base color with no reflective highlight at all.
#define WATER_REFLECTION_MODE 0  // Water/glass reflection quality [0 1 2 3]

// --- Glass ------------------------------------------------------------
#define GLASS_REFRACTION_STRENGTH 1.0 // How much the scene behind glass bends/wobbles, like real imperfect glass [0.0 0.5 1.0 1.5 2.0]
#define GLASS_GLARE_STRENGTH 1.0 // Sun glare/streak on CLEAR (non-tinted) glass when it's facing near the sun's reflection [0.0 0.5 1.0 1.5 2.0]

// --- Stars --------------------------------------------------------------
#define SHOW_STARS 1             // Render night sky stars [0 1]
#define STAR_SIZE 0.28           // Star dot radius - lower is smaller [0.15 0.2 0.28 0.4 0.55]

#define PI 3.14159265359

// Iris/OptiFine normally auto-inject MC_RENDER_STAGE_* macros alongside
// the `renderStage` uniform. Guarded fallback in case a particular
// loader build doesn't define it, so the sun/moon shader still compiles.
#ifndef MC_RENDER_STAGE_SUN
#define MC_RENDER_STAGE_SUN 4
#endif
#ifndef MC_RENDER_STAGE_MOON
#define MC_RENDER_STAGE_MOON 5
#endif

// ---------------------------------------------------------------------
// Dithering / noise
// ---------------------------------------------------------------------
float bayer4(vec2 p) {
    const mat4 bayer = mat4(
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0
    ) / 16.0;
    ivec2 i = ivec2(mod(p, 4.0));
    if (i.x == 0) { if (i.y == 0) return bayer[0][0]; if (i.y == 1) return bayer[0][1]; if (i.y == 2) return bayer[0][2]; return bayer[0][3]; }
    if (i.x == 1) { if (i.y == 0) return bayer[1][0]; if (i.y == 1) return bayer[1][1]; if (i.y == 2) return bayer[1][2]; return bayer[1][3]; }
    if (i.x == 2) { if (i.y == 0) return bayer[2][0]; if (i.y == 1) return bayer[2][1]; if (i.y == 2) return bayer[2][2]; return bayer[2][3]; }
    return i.y == 0 ? bayer[3][0] : (i.y == 1 ? bayer[3][1] : (i.y == 2 ? bayer[3][2] : bayer[3][3]));
}

// Guards a color against ever reaching colortex0 as NaN or an
// absurdly large HDR value. `x != x` is true for NaN under IEEE-754 in
// every GLSL implementation this pack targets, so this doesn't depend
// on isnan() (not guaranteed available pre-GLSL 1.30). This matters
// specifically for water/glass's colortex3 reads (refraction and SSR's
// reflection hit): a single bad pixel there doesn't stay a single bad
// pixel once it reaches composite1.fsh's bloom bright-pass and
// composite2.fsh's mipmap chain - mip-chain downsampling averages
// neighboring pixels together, and for true NaN that average is itself
// NaN, so one contaminated source pixel can spread across a growing
// fraction of the screen the further down the chain it's sampled from.
// That fits how far this pack's water/glass corruption was spreading
// past the actual geometry far better than a plain wrong-but-finite
// color sample would.
vec3 sanitizeColor(vec3 c) {
    bool bad = (c.r != c.r) || (c.g != c.g) || (c.b != c.b);
    return bad ? vec3(0.0) : clamp(c, vec3(0.0), vec3(50.0));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Trilinear value noise - cheap procedural 3D noise with no texture
// lookups, used to build the volumetric cloud density field.
float valueNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

// Classic 12-direction Perlin gradient set - genuine gradient noise
// (dot products of pseudo-random unit vectors with the offset from
// each lattice corner), not value noise. This is what was requested
// for the clouds specifically: value noise interpolates raw random
// numbers and tends to look slightly "blobby"/rounded at low octaves;
// gradient noise has a more organic, less uniformly-rounded look,
// which is why Perlin/gradient noise (not value noise) is the
// standard choice for cloud density fields in most shaderpacks.
const vec3 PERLIN_GRAD[12] = vec3[12](
    vec3(1.0, 1.0, 0.0), vec3(-1.0, 1.0, 0.0), vec3(1.0, -1.0, 0.0), vec3(-1.0, -1.0, 0.0),
    vec3(1.0, 0.0, 1.0), vec3(-1.0, 0.0, 1.0), vec3(1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0),
    vec3(0.0, 1.0, 1.0), vec3(0.0, -1.0, 1.0), vec3(0.0, 1.0, -1.0), vec3(0.0, -1.0, -1.0)
);

vec3 perlinGradDir(vec3 p) {
    int idx = int(hash13(p) * 12.0);
    idx = idx - (idx / 12) * 12; // manual modulo, avoids relying on % with int on all drivers
    return PERLIN_GRAD[idx];
}

vec3 perlinFade(vec3 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float perlinNoise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = perlinFade(f);

    float n000 = dot(perlinGradDir(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0));
    float n100 = dot(perlinGradDir(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
    float n010 = dot(perlinGradDir(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
    float n110 = dot(perlinGradDir(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
    float n001 = dot(perlinGradDir(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
    float n101 = dot(perlinGradDir(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
    float n011 = dot(perlinGradDir(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
    float n111 = dot(perlinGradDir(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z) * 0.5 + 0.5; // remap ~[-1,1] to [0,1]
}

float cloudFBM(vec3 p) {
    float sum = 0.0;
    float amp = 0.55;
    for (int i = 0; i < 4; i++) {
        sum += perlinNoise3D(p) * amp;
        p *= 2.05;
        amp *= 0.5;
    }
    return sum;
}

// ---------------------------------------------------------------------
// Cloud shadows - a cheap 2D stand-in for the volumetric clouds
// actually casting shadow on the world below them. The real clouds in
// composite.fsh raymarch a 3D noise field because the sky itself needs
// to look volumetric from every viewing angle; the ground only needs
// one bit of information from that same cloud layer - "is it thick
// directly overhead right now" - so this just projects straight up to
// the cloud layer's altitude and takes a single sample there, using
// the identical coordinate scale and wind drift as the real clouds so
// the shadow position/shape actually lines up with what's visible in
// the sky above.
// ---------------------------------------------------------------------
float cloudShadowFactor(vec3 cameraRelativeWorldPos) {
    const float cloudLayerY = 170.0;
    vec3 wind = vec3(frameTimeCounter * 0.9, 0.0, frameTimeCounter * 0.5);
    vec3 samplePos = vec3(cameraRelativeWorldPos.x, 0.0, cameraRelativeWorldPos.z) + cameraPosition + wind;
    samplePos.y = cloudLayerY;
    float n = cloudFBM(samplePos * 0.0055);
    float coverage = smoothstep(CLOUD_COVERAGE, CLOUD_COVERAGE + 0.34, n);
    coverage = clamp(coverage, 0.0, CLOUD_OPACITY);
    return mix(1.0, 0.45, coverage * CLOUD_SHADOW_STRENGTH);
}

// ---------------------------------------------------------------------
// Rain ripples - concentric rings that expand and fade on water
// surfaces while it's raining. Tiled across a jittered grid so many
// independent ripples are spawning/aging/expiring across the surface
// continuously, without needing to track individual raindrop impacts
// (a single-pass shader has no per-frame persistent state to do that
// with) - each grid cell just runs its own ripple on a looping phase
// offset from its neighbors, driven off a per-cell hash so they don't
// all pulse in lockstep.
// ---------------------------------------------------------------------
vec3 rainRippleNormal(vec2 worldXZ, float t) {
    vec2 cell = floor(worldXZ * 0.6);
    vec2 local = fract(worldXZ * 0.6) - 0.5;
    vec2 jitter = vec2(hash12(cell), hash12(cell + 91.7)) - 0.5;
    vec2 center = jitter * 0.7;
    float dist = length(local - center);

    float phase = fract(t * 0.6 + hash12(cell + 3.1));
    float ringRadius = phase * 0.9;
    float ring = 1.0 - smoothstep(0.0, 0.05, abs(dist - ringRadius));
    ring *= (1.0 - phase); // fades out as the ripple expands/ages

    vec2 grad = normalize(local - center + 0.0001) * ring * 0.4;
    return normalize(vec3(grad.x, 1.0, grad.y));
}

// ---------------------------------------------------------------------
// Underwater caustics - a wavy, net-like dancing-light pattern used
// both for the seabed glints under shallow water (gbuffers_water.fsh)
// and the full-screen shimmer while swimming (final.fsh). Built from
// the difference of two independently-drifting Perlin noise fields:
// where the two fields nearly cancel out, abs(n1-n2) sits close to 0,
// which after inverting + a sharpening power creates thin bright net
// lines - the same family of technique ("difference of two moving
// noise layers") behind most stylized real-time caustics, without
// needing an actual projected caustic texture or light-map.
// ---------------------------------------------------------------------
float causticPattern(vec2 worldXZ, float t) {
    vec2 p1 = worldXZ * 0.35 + vec2(t * 0.6, t * 0.4);
    vec2 p2 = worldXZ * 0.35 - vec2(t * 0.5, -t * 0.3) + 17.0;
    float n1 = perlinNoise3D(vec3(p1, t * 0.1));
    float n2 = perlinNoise3D(vec3(p2, t * 0.1 + 5.0));
    float net = 1.0 - abs(n1 - n2) * 2.0;
    return clamp(pow(max(net, 0.0), 4.0) * 2.2, 0.0, 1.0);
}

// ---------------------------------------------------------------------
// Water waves v2 (BSL/Complementary-style rewrite).
//
// The old system displaced the actual mesh vertices of the water
// quad's top face. Minecraft's water mesh is one flat, untessellated
// quad per block, and only the top face was being pushed up/down while
// the vertical "skirt" faces around it stayed put - on any pool with
// mixed depths this tore the mesh open at the seam between the raised
// top face and its still faces, which is what produced the jagged
// dark shard artifacts poking up out of the water in testing.
//
// New approach: the mesh is left completely flat (no vertex
// displacement at all - see gbuffers_water.vsh), and *all* wave motion
// is done per-pixel as a fake normal map, exactly how BSL and
// Complementary do it. A flat mesh can never tear, so this class of
// bug is structurally impossible now, not just tuned smaller.
// ---------------------------------------------------------------------

// Broad, LOW-frequency swell for actual VERTEX displacement (see
// gbuffers_water.vsh). Wavelength has to stay long relative to a block,
// since Minecraft's water is one flat, untessellated quad per block -
// short wavelengths here would facet into visible hard triangles when
// the mesh is physically raised/lowered. Fine ripple detail stays
// fragment-only (waterWaveNormal/waterRippleNormal below).
//
// Depends only on worldXZ (not Y, not face orientation), which is what
// makes it safe to apply to every water vertex - top face AND the
// vertical skirt faces around shorelines/depth changes. Any two
// vertices that share the same (x,z) - whether they're the top-face
// corner and the skirt-top corner below it, or the shared edge between
// two neighboring water columns - always compute the identical offset,
// so nothing can separate. That's the actual fix for the old tearing
// bug: it's not that vertex displacement is inherently unsafe, it's
// that only moving the top face while leaving the skirts behind was.
float waterHeightVertex(vec2 worldXZ, float t) {
    float h = 0.0;
    h += sin(dot(worldXZ, vec2( 0.90,  0.30)) * 0.16 + t * 0.70) * 0.55;
    h += sin(dot(worldXZ, vec2(-0.35,  0.95)) * 0.13 - t * 0.55) * 0.55;
    h += sin(dot(worldXZ, vec2( 0.15, -0.85)) * 0.09 + t * 0.40) * 0.35;
    return h * WATER_WAVE_HEIGHT;
}

// Five directional sine layers (different direction, frequency, speed,
// and weight each) summed together. Using distinct *directions* per
// layer (not just different frequencies along the same x/z axes) is
// what keeps the result from reading as a repeating grid - real chop
// is a jumble of wavefronts travelling different ways, not one grid of
// bumps scrolling diagonally.
//
// This feeds the fragment-only fake normal map, not geometry, so its
// amplitude is deliberately pushed harder than WATER_WAVE_HEIGHT alone
// (via NORMAL_WAVE_BOOST) for visibly lively chop - there's no
// faceting risk to worry about here since it never touches the mesh.
const float NORMAL_WAVE_BOOST = 1.35;
float waterWaveHeight(vec2 worldXZ, float t) {
    float h = 0.0;
    h += sin(dot(worldXZ, vec2( 0.90,  0.30)) * 0.55 + t * 1.35) * 0.40;
    h += sin(dot(worldXZ, vec2(-0.35,  0.95)) * 0.42 + t * 0.95) * 0.34;
    h += sin(dot(worldXZ, vec2( 0.15, -0.85)) * 0.90 + t * 1.85) * 0.16;
    h += sin(dot(worldXZ, vec2( 0.95,  0.55)) * 1.65 - t * 2.55) * 0.09;
    h += sin(dot(worldXZ, vec2(-0.65, -0.70)) * 3.05 + t * 3.30) * 0.045;
    return h * WATER_WAVE_HEIGHT * NORMAL_WAVE_BOOST;
}

// Central-difference normal from the height field above, plus a slow
// domain warp so the wave pattern drifts and never locks into an
// obviously periodic tile - same technique as before, kept because it
// works, just re-applied to the new height field.
vec3 waterWaveNormal(vec2 worldXZ, float t) {
    vec2 warp = vec2(
        valueNoise3D(vec3(worldXZ * 0.035, t * 0.04)),
        valueNoise3D(vec3(worldXZ * 0.035 + 19.0, t * 0.04))
    ) * 1.4;
    vec2 p = worldXZ + warp;

    float e = 0.14;
    float hL = waterWaveHeight(p - vec2(e, 0.0), t);
    float hR = waterWaveHeight(p + vec2(e, 0.0), t);
    float hD = waterWaveHeight(p - vec2(0.0, e), t);
    float hU = waterWaveHeight(p + vec2(0.0, e), t);
    return normalize(vec3((hL - hR) / (2.0 * e), 1.0, (hD - hU) / (2.0 * e)));
}

// Fine ripple layer on top of the broad waves above - short wavelength,
// low amplitude, fast-ish - gives close-up surface texture without
// needing a texture sample.
vec3 waterRippleNormal(vec2 worldXZ, float t) {
    float e = 0.10;
    vec2 p = worldXZ * 5.2 - 3.0;
    float freq = 1.0, tSpeed = 2.4;
    float hL = sin(dot(p - vec2(e,0.0), vec2(0.8,0.6)) * freq + t * tSpeed);
    float hR = sin(dot(p + vec2(e,0.0), vec2(0.8,0.6)) * freq + t * tSpeed);
    float hD = sin(dot(p - vec2(0.0,e), vec2(-0.5,0.9)) * freq - t * tSpeed * 0.8);
    float hU = sin(dot(p + vec2(0.0,e), vec2(-0.5,0.9)) * freq - t * tSpeed * 0.8);
    return normalize(vec3((hL - hR) * 0.15, 1.0, (hD - hU) * 0.15));
}

// Scattered twinkling highlight dots (the "glitter" you see raking
// across BSL/Complementary water in direct sunlight): a jittered point
// per grid cell that blinks in and out over time, independent of the
// broad wave normal so many small bright points can appear even on an
// otherwise calm patch of surface. Returns 0..1, meant to modulate a
// specular term, not to be used as a color on its own.
float waterSparkle(vec2 worldXZ, float t) {
    vec2 cell = worldXZ * 20.0;
    vec2 id = floor(cell);
    vec2 f = fract(cell) - 0.5;

    float n = hash12(id);
    vec2 jitter = vec2(hash12(id + 11.3), hash12(id + 57.1)) - 0.5;
    float d = length(f - jitter * 0.7);

    float twinkle = 0.5 + 0.5 * sin(t * 5.0 + n * 62.83);
    float sparkleActive = step(0.94, n); // only ~6% of cells ever sparkle
    return smoothstep(0.16, 0.0, d) * sparkleActive * twinkle;
}

// ---------------------------------------------------------------------
// Day / sunset / sunrise color + intensity curve.
// worldTime: 0 = sunrise, 6000 = noon, 12000 = sunset, 18000 = midnight.
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
// Day / sunset / sunrise color + intensity curve.
// worldTime: 0 = sunrise, 6000 = noon, 12000 = sunset, 18000 = midnight.
// sin(angle) naturally peaks at 6000 and troughs at 18000 with this
// phase, which is what we want - do NOT swap this for cos() without
// re-deriving the phase, that was the original bug (cos peaked at
// worldTime 12000/dusk instead of 6000/noon, making "night" render as
// bright as midday).
// ---------------------------------------------------------------------
float getDayFactor() {
    // 1.0 at noon, 0.0 at midnight, but sharpened into flat day/night
    // plateaus with a fast transition at actual dusk/dawn instead of a
    // slow sinusoid.
    //
    // The raw sin() value is technically "correct" (peaks at noon,
    // troughs at midnight) but its sides are too gradual: at tick 13000
    // - the very start of vanilla night, when mobs start spawning - it
    // was still returning ~0.37, i.e. the sky/ambient were still over a
    // third of the way toward full daylight brightness. Vanilla's own
    // actual light level drops fast right around dusk and stays flat
    // and dark all night, not a slow half-cycle fade.
    //
    // Fix: keep the same correctly-phased sin() value (so noon/midnight
    // alignment and the day<->night wraparound stay exactly right), but
    // push it through a steep smoothstep remap centered on 0.5. This
    // only changes how fast the *transition* happens, not where the
    // peaks are, so it can't reintroduce a phase bug - a monotonic
    // remap of an already-correct 0..1 curve stays correct at its
    // endpoints and just flattens the middle.
    float wt = mod(float(worldTime), 24000.0);
    float angle = (wt / 24000.0) * 2.0 * PI;
    float raw = clamp(sin(angle) * 0.5 + 0.5, 0.0, 1.0);
    return smoothstep(0.35, 0.65, raw);
}

float getSunVisibility() {
    // Same phase as getDayFactor, but with a steeper response so direct
    // light ramps up/down faster around sunrise/sunset instead of
    // lingering bright deep into the night.
    float wt = mod(float(worldTime), 24000.0);
    float angle = (wt / 24000.0) * 2.0 * PI;
    float h = sin(angle); // 1 at noon, -1 at midnight
    return clamp(h * 1.6 + 0.2, 0.0, 1.0);
}

float getDuskDawnFactor() {
    // Peaks at sunrise (worldTime 0) and sunset (worldTime 12000),
    // 0.0 at noon and midnight.
    float wt = mod(float(worldTime), 24000.0);
    float angle = (wt / 24000.0) * 2.0 * PI;
    return clamp(1.0 - abs(sin(angle)) * 1.5, 0.0, 1.0);
}

vec3 getSunColor() {
    float day   = getDayFactor();
    float dusk  = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);
    vec3 noonColor   = vec3(1.12, 1.03, 0.88);
    vec3 sunsetColor = vec3(1.5, 0.5, 0.18);
    vec3 nightColor  = vec3(0.05, 0.07, 0.13) * NIGHT_BRIGHTNESS;
    vec3 c = mix(nightColor, noonColor, day);
    c = mix(c, sunsetColor, dusk * (1.0 - day * 0.55));
    return c;
}

vec3 getAmbientSkyColor() {
    float day = getDayFactor();
    vec3 dayAmbient = vec3(0.62, 0.74, 0.92);

    // NIGHT_DARKNESS picks the base night ambient level. TRUE_BLACK_NIGHTS
    // is a separate, opt-in toggle on top of that: with it off (default),
    // night stays at a normal, still-navigable moonlit dimness; only when
    // it's explicitly turned on does night drop to a much darker level
    // where you genuinely need a light source to see, day or night. The
    // two used to be entangled (the darker numbers applied unconditionally
    // any time NIGHT_DARKNESS was 1 or 2), which is why night was pitch
    // black even with the true-black option left off.
    //
    // BUGFIX (round 11): the non-true-black tiers (0/1/2) were still
    // reading as too dark and a bit flat/monochrome to actually enjoy
    // looking at, per feedback after the split above. Brightened the
    // default (1) and vanilla-ish (0) tiers noticeably and pushed their
    // hue a little further toward a richer moonlit blue-violet instead
    // of a flat dark gray-blue - "very dark" (2) is left as-is, since
    // that tier's whole point is being the darker option to opt into.
#if NIGHT_DARKNESS == 2
    vec3 nightAmbient = vec3(0.014, 0.02, 0.045);
#elif NIGHT_DARKNESS == 1
    vec3 nightAmbient = vec3(0.048, 0.062, 0.125);
#else
    vec3 nightAmbient = vec3(0.078, 0.098, 0.185);
#endif
#if TRUE_BLACK_NIGHTS == 1
    nightAmbient *= 0.25;
#endif
    // NIGHT_BRIGHTNESS is a separate, purely additive-to-taste knob on
    // top of NIGHT_DARKNESS/TRUE_BLACK_NIGHTS: those two pick the "mood"
    // (how dark night looks), this just scales the end result brighter
    // for people who want to actually see more at night without
    // changing that mood/level choice.
    nightAmbient *= NIGHT_BRIGHTNESS;

    return mix(nightAmbient, dayAmbient, day) * mix(1.0, 0.55, rainStrength);
}

// ---------------------------------------------------------------------
// Horizon sky color - mirrors the horizon gradient computed in
// gbuffers_skybasic.fsh so that fog fading distant terrain out near the
// render-distance edge (see applyFog below) blends toward the SAME
// color the sky itself is showing at the horizon, rather than the flat
// vanilla fogColor uniform. Those two used to disagree (fogColor is a
// fixed, fairly neutral biome/dimension value that has no idea it's
// sunset or midnight), which is what produced a visible hard seam right
// at the horizon line between the sky gradient above and the fogged-out
// terrain below.
// ---------------------------------------------------------------------
vec3 getHorizonSkyColor() {
    float day = getDayFactor();
    float dusk = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);

    vec3 horizonDay  = vec3(0.70, 0.82, 0.96);
    vec3 horizonDusk = vec3(1.15, 0.45, 0.22);
    // Matches the getAmbientSkyColor brightening/hue push above, for the
    // same reason - the horizon and the general ambient light need to
    // stay consistent with each other or night reads as two different
    // moods stitched together at the skyline.
#if NIGHT_DARKNESS == 2
    vec3 horizonNight = vec3(0.018, 0.024, 0.05);
#elif NIGHT_DARKNESS == 1
    vec3 horizonNight = vec3(0.040, 0.052, 0.105);
#else
    vec3 horizonNight = vec3(0.060, 0.078, 0.145);
#endif
#if TRUE_BLACK_NIGHTS == 1
    horizonNight *= 0.2;
#endif
    horizonNight *= NIGHT_BRIGHTNESS;

    vec3 horizonC = mix(horizonNight, horizonDay, day);
    horizonC = mix(horizonC, horizonDusk, dusk * (1.0 - day * 0.4));
    horizonC *= mix(1.0, 0.45, rainStrength);
    return horizonC;
}

// ---------------------------------------------------------------------
// Exponential height + distance fog
// ---------------------------------------------------------------------
vec3 applyFog(vec3 color, vec3 fogCol, float viewDist, float fragY, float camY) {
    // BUGFIX: rain used to add up to +0.0018 density on top of the
    // 0.0006 clear-weather base - a 4x jump. Combined with vanilla's
    // own fogColor uniform, which during rain is a flat, fairly bright
    // gray-white with no atmospheric tinting of its own, that made
    // fog kick in thick enough at close/mid range to wash out most of
    // a rainy scene into a pale haze instead of a believable overcast
    // atmosphere. Rain should thicken fog, just nowhere near this much.
    // BUGFIX: 0.0006 base density was still washing out mid-distance
    // terrain even in clear weather with zero rain contribution (see
    // reference shots of distant mountains going pale/hazy well before
    // any believable atmospheric perspective distance) - the earlier
    // fix only addressed the rain-specific multiplier on top of this,
    // not the base value itself.
    float density = (0.00035 + rainStrength * 0.00035) * FOG_DENSITY;
    float heightFalloff = exp(-max(fragY + camY - 64.0, 0.0) * 0.012);
    float fogAmount = 1.0 - exp(-viewDist * density * mix(1.0, 2.2, heightFalloff));

    // BUGFIX: this used to hard-clamp to full fog color right at the
    // player's actual render distance (far*0.4 to far), on the
    // assumption that's where the world simply stops existing in
    // vanilla rendering. That assumption breaks with mods like Voxy
    // that keep rendering real (simplified/LOD) geometry well past
    // `far` - all of that extended terrain was getting blanketed in
    // solid fog color regardless of how well it was actually rendered,
    // which is what read as a washed-out haze instead of distant
    // terrain fading naturally into the horizon. Pushed the anchor out
    // to a much larger multiple of far so it acts as a distant backstop
    // for vanilla's hard pop-in edge without smothering anything a LOD
    // mod is still legitimately drawing - the exponential density term
    // above is what does the real atmospheric fading work now, the way
    // it naturally should for any actual visible distance.
    // BUGFIX (round 11): the VOXY_COMPAT branch here used to floor this
    // anchor to a large fixed distance (2200+ blocks) regardless of the
    // player's actual `far`. That was reasoned as "safe" on the
    // assumption the exponential density term above was already doing
    // all the real fading work and this anchor was just a backstop -
    // true for a Voxy user with an extended visible range, but VOXY_COMPAT
    // defaults ON for everyone, and for the ordinary case (no Voxy, `far`
    // at a normal 128-384 block vanilla render distance) flooring the
    // anchor to 2200+ blocks pushed it completely outside what's ever
    // actually visible - removing the backstop fog entirely rather than
    // just not mattering, which is a real regression, not a no-op.
    // Reverted to scaling purely off `far` for everyone; Voxy's own
    // extended terrain is better served by the separate, genuinely
    // distance-scaling haze blend in composite.fsh than by this pack
    // guessing at a fixed floor that may or may not match how far
    // Voxy is actually rendering clearly at any given moment.
    float farFogStart = far * 2.5;
    float farFogRange = max(far * 3.5, 32.0);
    float farFog = clamp((viewDist - farFogStart) / farFogRange, 0.0, 1.0);
    farFog = farFog * farFog * (3.0 - 2.0 * farFog);

    // BUGFIX: fogCol is vanilla's raw fogColor uniform, which during
    // rain is a fairly bright, flat gray-white with no idea what time
    // of day or how overcast the light actually is - blending straight
    // toward it at close range is what read as "white haze" rather than
    // rain atmosphere. Darkening/desaturating it toward the same
    // rain-dimmed ambient tone used elsewhere (see getAmbientSkyColor)
    // keeps close-range fog color-consistent with the rest of the
    // rainy lighting instead of standing out as a brighter, whiter
    // patch of its own.
    vec3 nearFogCol = mix(fogCol, fogCol * vec3(0.75, 0.78, 0.85), rainStrength);

    // As the far-edge term ramps up, shift the fog tint from the passed-
    // in fogCol (used for the close-range atmospheric/rain haze, which
    // still wants vanilla's fog color) toward the sky's own horizon
    // color - this is what keeps the render-distance edge from reading
    // as a mismatched, differently-colored band against the sky.
    vec3 edgeColor = mix(nearFogCol, getHorizonSkyColor(), farFog);

    fogAmount = max(fogAmount, farFog);
    fogAmount = clamp(fogAmount, 0.0, 1.0);
    return mix(color, edgeColor, fogAmount);
}

// ---------------------------------------------------------------------
// Henyey-Greenstein phase function for volumetric god rays
// ---------------------------------------------------------------------
float phaseHG(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// ---------------------------------------------------------------------
// Shadow sampling (PCF) - pass the shadow depth sampler explicitly.
// worldPos must be relative to the camera (feetPlayerPos style).
//
// Upgraded from a 3x3 box kernel to a 16-tap Poisson disc: a box kernel
// only has 8 distinct step directions, so shadow edges band into
// visible stairsteps once you look closely (particularly noticeable on
// the water depth work needing crisp, believable shadows). A Poisson
// disc samples in a jittered, non-grid-aligned pattern, which reads as
// a smooth soft edge instead at the same sample count.
//
// bias is exposed as a parameter (with a default-bias overload below
// for callers that don't need anything fancier) so callers can pass a
// slope-scaled bias - i.e. a bigger bias at grazing angles, where a
// fixed bias either acne's (too small) or peter-pans (too big) - one
// fixed constant can't be right for both a flat floor and a steep wall.
// ---------------------------------------------------------------------
const vec2 POISSON_DISC[16] = vec2[16](
    vec2(-0.94201624, -0.39906216), vec2( 0.94558609, -0.76890725),
    vec2(-0.09418410, -0.92938870), vec2( 0.34495938,  0.29387760),
    vec2(-0.91588581,  0.45771432), vec2(-0.81544232, -0.87912464),
    vec2(-0.38277543,  0.27676845), vec2( 0.97484398,  0.75648379),
    vec2( 0.44323325, -0.97511554), vec2( 0.53742981, -0.47373420),
    vec2(-0.26496911, -0.41893023), vec2( 0.79197514,  0.19090188),
    vec2(-0.24188840,  0.99706507), vec2(-0.81409955,  0.91437590),
    vec2( 0.19984126,  0.78641367), vec2( 0.14383161, -0.14100790)
);

float sampleShadowPCF(sampler2D shadowtex, vec3 shadowClipPos, float bias) {
    if (shadowClipPos.x < 0.0 || shadowClipPos.x > 1.0 ||
        shadowClipPos.y < 0.0 || shadowClipPos.y > 1.0 ||
        shadowClipPos.z < 0.0 || shadowClipPos.z > 1.0) {
        return 1.0;
    }

#if SOFT_SHADOWS == 1
    float texel = 1.0 / float(SHADOW_RES);
    // Rotate the whole disc per-pixel (cheap hash-based angle) so the
    // fixed 16-tap pattern doesn't itself read as a repeating texture
    // of shadow edges across flat, evenly-lit ground.
    float angle = hash12(shadowClipPos.xy * float(SHADOW_RES)) * 6.28318530718;
    float ca = cos(angle), sa = sin(angle);
    mat2 rot = mat2(ca, -sa, sa, ca);

    // --- Blocker search (contact hardening) -------------------------
    // A flat-radius PCF blur makes every shadow edge equally soft,
    // whether it's a foot touching the ground (should be a crisp
    // near-hard line) or a tree canopy's shadow forty blocks away
    // (should be a wide, diffuse penumbra). Sampling a wider ring
    // first to find the AVERAGE depth of whatever's actually occluding
    // this point, then scaling the real PCF kernel by how far past
    // that blocker the receiver sits, gets both right with one
    // technique instead of picking a single compromise radius.
    float blockerSum = 0.0;
    float blockerCount = 0.0;
    for (int i = 0; i < 16; i++) {
        vec2 offset = (rot * POISSON_DISC[i]) * texel * 3.0;
        float d = texture2D(shadowtex, shadowClipPos.xy + offset).r;
        if (d < shadowClipPos.z - bias) {
            blockerSum += d;
            blockerCount += 1.0;
        }
    }

    float penumbraScale = 1.0;
    if (blockerCount > 0.5) {
        float avgBlocker = blockerSum / blockerCount;
        float penumbraRatio = (shadowClipPos.z - avgBlocker) / max(avgBlocker, 0.0005);
        penumbraScale = clamp(1.0 + penumbraRatio * 60.0 * SHADOW_SOFTNESS, 1.0, 5.0);
    }

    float shadow = 0.0;
    for (int i = 0; i < 16; i++) {
        vec2 offset = (rot * POISSON_DISC[i]) * texel * 1.6 * penumbraScale;
        float depthSample = texture2D(shadowtex, shadowClipPos.xy + offset).r;
        shadow += (shadowClipPos.z - bias <= depthSample) ? 1.0 : 0.0;
    }
    return shadow / 16.0;
#else
    float depthSample = texture2D(shadowtex, shadowClipPos.xy).r;
    return (shadowClipPos.z - bias <= depthSample) ? 1.0 : 0.0;
#endif
}

float sampleShadowPCF(sampler2D shadowtex, vec3 shadowClipPos) {
    return sampleShadowPCF(shadowtex, shadowClipPos, 0.0022);
}

// Soft-filtered colored-shadow tint lookup. The original approach took
// one unfiltered texel from shadowcolor0, which faithfully reproduces
// the shadow map's own texel grid AND the caster mesh's triangle edges
// at that resolution - in practice a stained-glass window overhead
// showed up as a hard-edged, blocky/triangular patch of color on the
// surface below rather than a soft tinted glow, most visible on flat
// ceilings/floors directly under a window. A small box blur over
// shadowcolor0 (same texel size as the depth PCF above, scaled by the
// same SHADOW_SOFTNESS setting) smooths that into a soft-edged patch -
// the same fix in spirit as sampleShadowPCF's own move from a single
// tap to a filtered kernel. Takes the sampler as a parameter (like
// sampleShadowPCF above) rather than assuming a global `shadowcolor0`,
// since not every program that includes this file declares that
// uniform.
vec4 sampleShadowTintPCF(sampler2D shadowcolorSampler, vec2 shadowUV) {
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
        return vec4(0.0);
    }
    float texel = 1.0 / float(SHADOW_RES);
    vec4 sum = vec4(0.0);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[0] * texel * 2.4 * SHADOW_SOFTNESS);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[1] * texel * 2.4 * SHADOW_SOFTNESS);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[2] * texel * 2.4 * SHADOW_SOFTNESS);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[3] * texel * 2.4 * SHADOW_SOFTNESS);
    return sum * 0.25;
}

// Wide-radius sample of the same colored-shadow buffer, used to let a
// bit of a stained-glass window's tint bleed onto surfaces just outside
// its own sharp shadow silhouette - a wall or floor tile a couple of
// blocks to the side of a window, which sampleShadowTintPCF's tight
// radius above would never catch since there's no caster directly
// overhead there at all. Real light through a window scatters somewhat
// beyond a razor-sharp edge rather than stopping dead at it; this is a
// stylized stand-in for that, not a physically-simulated bounce. See
// the call sites in gbuffers_terrain.fsh / gbuffers_water.fsh /
// gbuffers_entities.fsh for how it combines with the tight sample.
vec4 sampleShadowTintBleed(sampler2D shadowcolorSampler, vec2 shadowUV) {
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
        return vec4(0.0);
    }
    float bleedRadius = (1.0 / float(SHADOW_RES)) * 22.0 * SHADOW_SOFTNESS;
    vec4 sum = vec4(0.0);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[4] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[5] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[6] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[7] * bleedRadius);
    return sum * 0.25;
}

// Slope-scaled shadow bias: grazing-angle surfaces (low NdotL) need a
// bigger depth bias to avoid self-shadowing acne, but a bias that big
// on a directly-lit flat surface visibly detaches the shadow from its
// caster ("peter-panning"). Scaling bias by how oblique the surface is
// to the light gets both right instead of picking one fixed compromise.
float slopeScaledBias(float NdotL) {
    return mix(0.0055, 0.0016, clamp(NdotL, 0.0, 1.0));
}

// Softly fades shadow strength back to fully-lit as a surface
// approaches the outer edge of the shadow map's draw distance, instead
// of the hard pop straight from "shadowed" to "lit" that otherwise
// happens the instant a fragment's shadow-clip position steps outside
// [0,1] (sampleShadowPCF's own out-of-bounds check returns a flat 1.0
// with no transition at all - correct at the boundary, but with
// nothing easing into it). Only needs horizontal distance, since
// SHADOW_DISTANCE itself is a horizontal draw-distance figure.
float shadowDistanceFadeFactor(vec3 cameraRelativeWorldPos) {
    float dist = length(cameraRelativeWorldPos.xz);
    return smoothstep(SHADOW_DISTANCE * 0.75, SHADOW_DISTANCE * 0.98, dist);
}

vec3 worldToShadowClip(vec3 playerRelativePos) {
    vec4 shadowViewPos = shadowModelView * vec4(playerRelativePos, 1.0);
    vec4 shadowClipPos = shadowProjection * shadowViewPos;
    shadowClipPos.xyz /= shadowClipPos.w;
    return shadowClipPos.xyz * 0.5 + 0.5;
}

vec3 commonReconstructViewPos(vec2 uv, float depth, mat4 projInv) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * clip;
    return viewPos.xyz / viewPos.w;
}

// Screen-space "sun-only" contact shadow (SHADOW_MODE 1/2): marches a
// short ray from the fragment toward the sun/moon through view space,
// projecting each step back to screen space and testing it against the
// opaque depth buffer. This is a real per-pixel ray march against scene
// depth - the same technique some other packs market as "raytraced
// shadows" - deliberately kept SHORT range, since a screen-space ray can
// only ever see what's already on screen; it can't reach off past the
// edge of frame or behind the camera the way a true scene raytrace
// could. It's meant to layer extra close-range contact detail (corners,
// thin objects, block edges the shadow map's finite texel resolution
// blurs away) on top of the existing shadow map, not replace it.
// Returns 1.0 = fully lit along this short ray, 0.0 = occluded.
//
// BUGFIX: this used to return a hard, undithered 0.0/1.0 - every pixel
// tested the exact same fixed step positions along its own ray, so
// whether a given pixel's ray happened to clip a nearby edge (a cactus,
// a dug-out block corner, any small close occluder) was basically
// deterministic per-pixel. The occluded region's silhouette came out as
// a crisp, faceted polygon - a solid-looking geometric shape sitting on
// the ground - instead of blending into the shadow map's soft penumbra.
// Dithering the ray's starting phase per-pixel (same ordered 4x4 bayer
// pattern already used for SSAO's sample rotation and shadow PCF
// elsewhere in this pack) means neighboring pixels test slightly
// different points along the ray, breaking that hard edge into a fine
// dither the eye reads as a soft boundary instead of a solid cutout.
float screenSpaceSunShadow(sampler2D depthtex, mat4 projInv, vec3 viewPos, vec3 viewNormalDir, int steps, float range, vec2 screenCoord) {
    vec3 sunDirView = normalize(shadowLightPosition);
    // Small normal offset so the ray doesn't immediately self-intersect
    // the very surface it's marching away from.
    vec3 rayPos = viewPos + viewNormalDir * 0.04;
    float stepSize = range / float(steps);

    // Dither the starting phase by up to one full step, so the set of
    // depths actually sampled shifts continuously from pixel to pixel
    // instead of every pixel marching the identical fixed ladder.
    rayPos += sunDirView * (bayer4(screenCoord) * stepSize);

    for (int i = 0; i < steps; i++) {
        rayPos += sunDirView * stepSize;

        vec4 clip = gbufferProjection * vec4(rayPos, 1.0);
        if (clip.w <= 0.0) break;
        vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

        float sceneDepthRaw = texture2D(depthtex, uv).r;
        if (sceneDepthRaw >= 0.9999) continue; // sky pixel, nothing to occlude against

        vec3 sceneViewPos = commonReconstructViewPos(uv, sceneDepthRaw, projInv);
        // Same "ray has reached/passed the real surface" hit test used
        // by the water/glass SSR trace elsewhere in this pack.
        if (rayPos.z <= sceneViewPos.z + 0.1) return 0.0;
    }
    return 1.0;
}

// Turns the raw (albedo.rgb, tintStrength) sample from shadowcolor0
// into the actual tint applied to a lit surface. Two things beyond a
// flat mix: the color is pushed a bit further from gray toward its own
// hue (a faint wash barely reads as "colored light" - stained glass
// should look clearly colored), and a slow, subtle per-pixel shimmer is
// layered on so a big stained-glass window's light patch isn't
// perfectly static, the way real light through slightly uneven glass
// never quite is.
//
// BUGFIX: COLORED_GLASS_STRENGTH was declared as a setting (and given
// real per-profile values - Mid 1.0, High 1.3, Ultra 1.6) but never
// actually referenced anywhere in the shading code, so the slider in
// the shader options screen was a complete no-op. Now scales how far
// the tint gets pushed from gray toward its full saturated hue -
// COLORED_GLASS_STRENGTH:0 reads as neutral/uncolored light,
// COLORED_GLASS_STRENGTH:1.6 (Ultra) noticeably more vivid than the old
// fixed 1.35.
vec3 computeShadowTint(vec4 rawTint, vec3 worldPos) {
    float luma = dot(rawTint.rgb, vec3(0.299, 0.587, 0.114));
    vec3 vivid = mix(vec3(luma), rawTint.rgb, 1.35 * COLORED_GLASS_STRENGTH);
    float shimmer = 0.92 + 0.08 * sin(frameTimeCounter * 0.6 + worldPos.x * 0.3 + worldPos.z * 0.2);
    return mix(vec3(1.0), vivid * shimmer, clamp(rawTint.a, 0.0, 1.0));
}

// ---------------------------------------------------------------------
// Tonemap + color grading
// ---------------------------------------------------------------------
vec3 acesFilm(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ---------------------------------------------------------------------
// Per-biome color identity. Iris provides biome_category as a real
// uniform (not something faked from vertex colors) identifying the
// player's current biome category, comparable against predefined
// constants (CAT_JUNGLE, CAT_DESERT, CAT_TAIGA, etc.) that Iris injects
// automatically once this uniform is declared - the same mechanism
// already used for renderStage/MC_RENDER_STAGE_SUN elsewhere in this
// pack. This is a full-screen grade (color temperature nudge +
// saturation), not per-block tinting like the vColor-based work in
// gbuffers_terrain.fsh - the two are complementary: vColor tinting
// covers grass/foliage/water on a per-block basis, this covers
// everything else (stone, sky, fog, the player's own view) so an entire
// biome carries a bit of its own mood rather than just its foliage.
// Deliberately gentle throughout - meant to read as "this place feels
// different," not a heavy filter slapped over the whole screen.
vec3 getBiomeGradeTint() {
    if (biome_category == CAT_JUNGLE)   return vec3(-0.010,  0.015, -0.010); // lush, slightly cooler/greener shadows
    if (biome_category == CAT_DESERT)   return vec3( 0.020,  0.010, -0.020); // warm sand
    if (biome_category == CAT_MESA)     return vec3( 0.035,  0.005, -0.025); // strong warm red-orange
    if (biome_category == CAT_SAVANNA)  return vec3( 0.025,  0.010, -0.020); // warm golden
    if (biome_category == CAT_TAIGA)    return vec3(-0.015,  0.000,  0.020); // cool blue-green
    if (biome_category == CAT_ICY)      return vec3(-0.010,  0.005,  0.025); // cool blue-white
    if (biome_category == CAT_OCEAN)    return vec3(-0.015,  0.000,  0.020); // cool blue
    if (biome_category == CAT_SWAMP)    return vec3(-0.010,  0.005, -0.015); // murky green
    if (biome_category == CAT_MUSHROOM) return vec3( 0.015, -0.005,  0.015); // faint otherworldly magenta
    if (biome_category == CAT_THE_END)  return vec3( 0.005,  0.015, -0.010); // pale sickly yellow-green
    if (biome_category == CAT_NETHER)   return vec3( 0.030, -0.005, -0.020); // hot red
    return vec3(0.0); // plains, forest, beach, river, extreme hills, none: no shift
}

float getBiomeGradeSaturation() {
    if (biome_category == CAT_JUNGLE)   return 1.08;
    if (biome_category == CAT_MESA)     return 1.05;
    if (biome_category == CAT_SAVANNA)  return 1.05;
    if (biome_category == CAT_DESERT)   return 0.92;
    if (biome_category == CAT_TAIGA)    return 0.90;
    if (biome_category == CAT_SWAMP)    return 0.85;
    return 1.0;
}

vec3 colorGrade(vec3 color) {
    // Saturation
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, SATURATION);

    // Per-biome color identity (see getBiomeGradeTint/Saturation above)
    float biomeLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(biomeLuma), color, getBiomeGradeSaturation());
    color += getBiomeGradeTint();

    // Subtle day/night warmth push (warmer at sunset/sunrise, cooler at night)
    float dusk = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);
    float night = 1.0 - getDayFactor();
    vec3 warmShift = vec3(WARMTH * 0.6, WARMTH * 0.15, -WARMTH * 0.5) * dusk;
    vec3 coolShift = vec3(-WARMTH * 0.3, -WARMTH * 0.05, WARMTH * 0.5) * night * 0.6;
    color += warmShift + coolShift;

    // Split toning: a faint cool push in the shadows and warm push in
    // the highlights, independent of time-of-day. This is the same
    // "temperature split" trick behind the filmic look in BSL,
    // Complementary Reimagined, and Makeup - a single flat warmth shift
    // across the whole tonal range reads flatter than nudging shadows
    // and highlights in slightly opposite directions.
    float toneLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 shadowTone = vec3(-0.015, -0.005, 0.02);
    vec3 highlightTone = vec3(0.02, 0.008, -0.02);
    color += mix(shadowTone, highlightTone, smoothstep(0.15, 0.85, toneLuma));

    // Gentle filmic S-curve contrast. Unlike a lift-gamma-gain formula,
    // this leaves near-black (0.0) at 0.0 and only mildly pulls midtones
    // outward, so shadows stay dark instead of washing out to gray.
    color = clamp(color, 0.0, 1.0);
    color = color * color * (3.0 - 2.0 * color); // smoothstep-shaped contrast
    color = pow(color, vec3(0.94));              // tiny gamma polish, preserves 0.0

    return clamp(color, 0.0, 1.0);
}

// ---------------------------------------------------------------------
// Soft highlight compression for raw (pre-tonemap, pre-albedo) lighting.
// Ambient sky light and direct sun light are both additive, and in full
// daylight their sum can comfortably exceed 1.0 even before hitting a
// high-albedo surface. On dark/mid-toned textures that headroom just
// gets soaked up by the tonemapper later and nothing looks wrong, but
// on near-white textures (snow, white/diorite-ish stone, sand) it was
// enough to push the lit result so far past 1.0 that ACES + the
// contrast curve in colorGrade() both flatten it straight to a
// featureless white block - the "hyper-exposed" look. This leaves
// anything at or below 1.0 completely untouched (so normal terrain in
// normal light is unaffected) and only softly rolls off values above
// that with a slow logarithmic curve instead of letting them grow
// linearly forever, which keeps enough separation between "very bright"
// and "extremely bright" for the surface's own shading/texture detail
// to still read after tonemapping.
// ---------------------------------------------------------------------
vec3 softenHighlights(vec3 lighting) {
    float m = max(max(lighting.r, lighting.g), lighting.b);
    if (m <= 1.0) return lighting;
    float compressed = 1.0 + log(m) * 0.6;
    return lighting * (compressed / m);
}

// ---------------------------------------------------------------------
// Foliage canopy occlusion (forests/jungles reading too flatly lit).
//
// The existing colored-shadow mechanism (sampleShadowTintPCF/
// computeShadowTint, see shadow.fsh) already tints light passing through
// leaves, but it barely DARKENS it: leaves only write a modest 0.35 alpha
// into shadowcolor0 (deliberately less than glass's 0.6, so a single leaf
// block doesn't read as heavily opaque), and that alpha then gets run
// through GLASS_SKYLIGHT_STRENGTH's own gentle mix(1.0, 0.45, ...) curve
// - tuned for actual window glass, not a many-layers-deep tree canopy.
// The net effect measured out to roughly a 10% darkening under a solid
// leaf block, nowhere near the 60-80% real dappled forest shade drops to.
//
// Rather than trying to distinguish "this caster was a leaf, not a glass
// pane" from shadowcolor0's single alpha channel (materials share that
// channel, and COLORED_GLASS_STRENGTH scales all of them together, so a
// given alpha value can't be reliably mapped back to a material at the
// shading side), this reuses the PCF shadow test itself: `shadow` already
// measures visibility against shadowtex1 (OPAQUE casters only), and
// sampling the identical PCF kernel against shadowtex0 (ALL casters,
// including leaves/glass/ice) gives visibility against everything. Their
// difference is exactly the soft, antialiased fraction of this pixel's
// light that's being blocked specifically by a translucent-only caster
// overhead - a real canopy density estimate, already dithered/rotated by
// the same kernel as the rest of this pack's shadow work, with no new
// render target or per-material bookkeeping needed. It also naturally
// reads stronger under a continuous leaf canopy (most of the kernel
// stays occluded) than under a single small glass pane (most of the
// kernel still sees open sky past its edges), so it biases correctly
// toward "trees get real shade, a stray window doesn't" on its own.
float translucentCanopyOcclusion(sampler2D shadowtex0Sampler, vec3 shadowClipPos, float bias, float opaqueShadow) {
    if (FOLIAGE_SHADOW_STRENGTH <= 0.0) return 1.0;
    float shadowAllCasters = sampleShadowPCF(shadowtex0Sampler, shadowClipPos, bias);
    float canopyDensity = clamp(opaqueShadow - shadowAllCasters, 0.0, 1.0);
    return mix(1.0, 1.0 - FOLIAGE_SHADOW_STRENGTH, canopyDensity);
}

// Dusk/dawn-widened version of sampleShadowTintBleed (see the base
// version above for the technique). Real light scattering through a
// window spreads further across a room at low sun angles than at
// noon - a shaft of golden-hour light raking almost horizontally
// through stained glass lights up a much bigger patch of floor than the
// same window does at midday. Scales the existing bleed radius by the
// dusk/dawn factor instead of introducing a second, separate bleed pass.
vec4 sampleShadowTintBleedDynamic(sampler2D shadowcolorSampler, vec2 shadowUV) {
#if GLASS_BLEED_DYNAMIC_SPREAD == 1
    float duskFactor = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);
    float spread = mix(1.0, GLASS_BLEED_DUSK_MULTIPLIER, duskFactor);
#else
    float spread = 1.0;
#endif
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
        return vec4(0.0);
    }
    float bleedRadius = (1.0 / float(SHADOW_RES)) * 22.0 * SHADOW_SOFTNESS * spread;
    vec4 sum = vec4(0.0);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[4] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[5] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[6] * bleedRadius);
    sum += texture2D(shadowcolorSampler, shadowUV + POISSON_DISC[7] * bleedRadius);
    // A wider radius dilutes the average toward empty (alpha 0) space
    // faster than the tint itself fades in real light scatter, so the
    // raw average is boosted back up by roughly how much the radius grew
    // - keeps the bled patch's peak strength closer to constant as it
    // widens, rather than also reading fainter and fainter with it.
    return (sum * 0.25) * mix(1.0, sqrt(spread), 0.6);
}

// ---------------------------------------------------------------------
// Ocean biome temperature identity.
//
// BUGFIX (round 11): the original version of this function pushed color
// based on Iris's `temperature` uniform, on the assumption that it
// differs meaningfully across ocean/cold_ocean/lukewarm_ocean/warm_ocean
// the way their names suggest. It doesn't - confirmed against Mojang bug
// MC-240396: every ocean variant except frozen_ocean shares the exact
// same internal temperature value (0.5). That's a real, long-standing
// vanilla quirk (it's actually why those biomes' grass color looks
// wrong too), not something specific to this pack, but it meant the
// "warmth" this function computed was identical for cold_ocean and
// regular ocean - visibly no different at all, which is exactly what
// testing showed.
//
// BUGFIX (round 12, critical): the round-11 replacement extrapolated
// baseColor away from an assumed "neutral" ocean-blue value
// (result = baseColor + (baseColor-neutral)*0.8) to exaggerate whatever
// real per-biome hue was already there. That's unbounded linear
// extrapolation, not a blend - at typical ocean depth, baseColor is
// close to deepTint (see gbuffers_water.fsh), which sits far from the
// assumed neutral in every channel, and the extrapolation drove ALL
// THREE channels negative at once. Negative color values aren't
// clamped anywhere before they reach bloom/tonemap further down the
// pipeline, and pushing them back through that math is exactly what
// was turning ocean water blood-red instead of blue - a completely
// different, much worse failure than the "does nothing" bug it
// replaced. A mix() toward a fixed target color, by construction,
// can never leave the range between its two inputs, so it can't
// repeat this failure mode. `temperature` is kept for the one thing
// it's genuinely correct about: frozen_ocean really does report 0.0
// while every other ocean variant reports 0.5, so it still gets a
// real, bounded icy push. Beyond that, there isn't a reliable signal
// this pack has access to for separating warm/lukewarm/cold apart -
// the real per-biome water color (vColor) already blended into
// baseColor upstream in gbuffers_water.fsh is what does that, subtly
// but correctly, and this function no longer tries to fight it.
// BUGFIX (round 13): went back and added real warm/cold differentiation
// beyond the frozen-only push above, this time staying strictly within
// mix()'s bounded blend (never extrapolating past either endpoint - see
// the round-12 note just above on why that matters). Reads vColor's own
// hue directly - vanilla's warm/lukewarm ocean colors lean more green
// relative to blue than cold/cold-deep ocean does, which is real,
// per-biome data (unlike `temperature`). Passed in explicitly as a
// parameter rather than assumed as an in-scope global, since this file
// is #included before the calling shader's own `varying vec4 vColor`
// declaration and can't safely reference it directly.
vec3 getOceanTemperatureTint(vec3 baseColor, vec3 biomeWaterColor) {
    if (biome_category != CAT_OCEAN) return baseColor;

    float warmLean = clamp((biomeWaterColor.g - biomeWaterColor.b) * 4.0 + 0.5, 0.0, 1.0);
    float leanStrength = clamp(abs(biomeWaterColor.g - biomeWaterColor.b) * 8.0, 0.0, 1.0);
    vec3 tropical = vec3(0.10, 0.55, 0.50);
    vec3 icy      = vec3(0.45, 0.60, 0.68);
    vec3 target = mix(icy, tropical, warmLean);
    baseColor = mix(baseColor, target, clamp(0.4 * OCEAN_TEMPERATURE_TINT, 0.0, 0.65) * leanStrength);

    if (temperature < 0.2) {
        baseColor = mix(baseColor, vec3(0.55, 0.68, 0.78), clamp(0.25 * OCEAN_TEMPERATURE_TINT, 0.0, 1.0));
    }
    return baseColor;
}

// ---------------------------------------------------------------------
// Fireflies - small drifting glow-points over grass/foliage at night in
// forest/jungle/swamp biomes. Purely a per-pixel procedural field (no
// particle system available at this shading stage), built the same way
// as waterSparkle: a jittered point per grid cell that's only "active" in
// a small fraction of cells, drifting on a slow looping path so it reads
// as a wandering point of light rather than a fixed twinkling grid.
float fireflyField(vec3 worldPos, float t) {
    vec3 cellPos = worldPos * 0.7;
    vec3 cell = floor(cellPos);
    float active = hash13(cell);
    if (active < 0.92) return 0.0; // sparse - most cells have no firefly

    // Slow wandering drift within (and slightly beyond) the cell, so it
    // doesn't read as pinned to a grid.
    float phase = t * 0.5 + active * 62.83;
    vec3 drift = vec3(sin(phase * 0.9), sin(phase * 1.3 + 1.7) * 0.6, cos(phase * 0.8)) * 0.6;
    vec3 local = fract(cellPos) - 0.5 - drift;
    float d = length(local);

    float blink = 0.4 + 0.6 * (0.5 + 0.5 * sin(phase * 2.2));
    return smoothstep(0.22, 0.0, d) * blink;
}

// ---------------------------------------------------------------------
// Aurora borealis - soft drifting color ribbons high in the night sky
// over cold biomes. Stylized (a real aurora is a magnetosphere effect
// with no connection to ground biome), but a nice bit of atmosphere for
// taiga/icy nights, and thematically fitting for a pack about light
// bending in unusual ways. Built from a domain-warped FBM band mapped
// onto viewing elevation, colored with a green-to-violet gradient like
// a real aurora's altitude-dependent emission colors.
vec3 auroraColor(vec3 viewDir, float t) {
    if (viewDir.y < 0.05) return vec3(0.0);
    float band = cloudFBM(vec3(viewDir.x * 3.0 + t * 0.03, viewDir.z * 3.0 - t * 0.02, t * 0.015));
    float ribbon = smoothstep(0.35, 0.55, band) * smoothstep(0.85, 0.55, band);
    float elevationMask = smoothstep(0.05, 0.35, viewDir.y) * smoothstep(1.0, 0.6, viewDir.y);
    float shimmer = 0.7 + 0.3 * sin(t * 0.8 + viewDir.x * 8.0);
    vec3 low  = vec3(0.10, 0.85, 0.45); // green
    vec3 high = vec3(0.45, 0.25, 0.85); // violet
    vec3 col = mix(low, high, clamp(band * 1.3, 0.0, 1.0));
    return col * ribbon * elevationMask * shimmer;
}

#endif // REFRACT_COMMON
