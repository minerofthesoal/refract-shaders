#version 120
/* Refract Shaders - gbuffers_skybasic.fsh */

#include "/lib/common.glsl"

varying vec3 viewDir;
varying vec4 vColor;

/* RENDERTARGETS: 0,1 */

float starField(vec3 dir) {
#if SHOW_STARS == 0
    return 0.0;
#endif
    // Same coarse per-cell placement/density as before (a cell "has a
    // star" or doesn't, based on a hash threshold), but now renders it
    // as an actual small round dot with a soft edge instead of a single
    // flat-shaded grid cell - that's what makes the size independently
    // controllable via STAR_SIZE rather than being tied to the grid's
    // own cell size, and gives a much less blocky point of light.
    vec3 p = dir * 380.0;
    vec3 cell = floor(p);
    float n = hash12(cell.xz + cell.y * 17.0);
    if (n < 0.9975) return 0.0;

    vec3 frac = p - cell;
    vec2 jitter = vec2(hash12(cell.xy + 3.1), hash12(cell.yz + 7.7));
    float d = length(frac.xz - jitter);
    float twinkle = 0.7 + 0.3 * sin(frameTimeCounter * (1.2 + n * 2.5) + n * 30.0);
    return smoothstep(STAR_SIZE, 0.0, d) * twinkle;
}

void main() {
    vec3 dir = normalize(viewDir);

    float horizon = clamp(1.0 - abs(dir.y), 0.0, 1.0);
    float up = clamp(dir.y, 0.0, 1.0);

    float day = getDayFactor();
    float dusk = clamp(1.0 - abs(getSunVisibility() - 0.45) * 2.6, 0.0, 1.0);

    vec3 zenithDay   = vec3(0.30, 0.52, 0.92);
    vec3 horizonDay  = vec3(0.70, 0.82, 0.96);
    vec3 zenithDusk  = vec3(0.22, 0.16, 0.32);
    vec3 horizonDusk = vec3(1.15, 0.45, 0.22);
    // Same NIGHT_DARKNESS + TRUE_BLACK_NIGHTS split as getAmbientSkyColor
    // - see the note there. Off by default = a normal moonlit night sky,
    // not pitch black. Brightened/re-hued the same way as
    // getAmbientSkyColor's non-true-black tiers - a richer moonlit
    // blue-violet instead of a flat dark gray, and noticeably more
    // visible without needing to opt into a brighter darkness tier.
#if NIGHT_DARKNESS == 2
    vec3 zenithNight = vec3(0.009, 0.012, 0.03);
    vec3 horizonNight= vec3(0.018, 0.024, 0.05);
#elif NIGHT_DARKNESS == 1
    vec3 zenithNight = vec3(0.020, 0.026, 0.062);
    vec3 horizonNight= vec3(0.040, 0.052, 0.105);
#else
    vec3 zenithNight = vec3(0.026, 0.034, 0.078);
    vec3 horizonNight= vec3(0.060, 0.078, 0.145);
#endif
#if TRUE_BLACK_NIGHTS == 1
    zenithNight *= 0.2;
    horizonNight *= 0.2;
#endif
    zenithNight *= NIGHT_BRIGHTNESS;
    horizonNight *= NIGHT_BRIGHTNESS;

    vec3 zenith  = mix(zenithNight, zenithDay, day);
    vec3 horizonC= mix(horizonNight, horizonDay, day);
    zenith  = mix(zenith, zenithDusk, dusk * (1.0 - day * 0.5));
    horizonC= mix(horizonC, horizonDusk, dusk * (1.0 - day * 0.4));

    vec3 sky = mix(zenith, horizonC, pow(horizon, 1.4));
    sky = mix(sky, fogColor, 0.12 * horizon);
    sky *= mix(1.0, 0.45, rainStrength);

    // Stars fade in at night, fade out near horizon and during day.
    float starVisibility = clamp((1.0 - day) - dusk * 0.4, 0.0, 1.0) * up;
    float stars = starField(dir) * starVisibility;
    sky += vec3(stars);

    // --- New feature: aurora borealis over cold biomes ---------------
    // Stylized, not a physical simulation (a real aurora has nothing to
    // do with ground biome), but it's a nice bit of atmosphere for
    // taiga/icy/snowy nights and fits this pack's own "light bending in
    // unusual ways" identity. Gated on Iris's `temperature` uniform
    // rather than biome_category, since biome_category has no single
    // "cold" bucket that cleanly covers taiga + icy peaks + snowy
    // plains + frozen ocean shoreline together the way a temperature
    // threshold does.
#if AURORA == 1
    if (AURORA_STRENGTH > 0.0 && temperature < 0.3) {
        float coldness = clamp((0.3 - temperature) / 0.3, 0.0, 1.0);
        vec3 aurora = auroraColor(dir, frameTimeCounter) * starVisibility * coldness * AURORA_STRENGTH;
        sky += aurora;
    }
#endif

    gl_FragData[0] = vec4(sky, 1.0);
    gl_FragData[1] = vec4(0.5, 0.5, 1.0, 0.0);
}
