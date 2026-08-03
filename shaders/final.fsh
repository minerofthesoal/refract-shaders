#version 120
/* Refract Shaders - final.fsh
   Last stage: tonemap the HDR buffer to display range, apply cinematic
   color grading, vignette, dither, and (new) a real underwater effect:
   screen-space sine distortion of the whole frame + blue-green tint +
   drifting caustic shimmer + tighter vignette - the same family of
   technique BSL/Bliss use for their underwater look (confirmed via
   BSL's own changelog: "applies screen distortion while underwater"),
   not just a flat fog-color swap. */

#include "/lib/common.glsl"

uniform sampler2D colortex0;

varying vec2 texcoord;

void main() {
    vec2 uv = texcoord;

    bool underwater = (isEyeInWater == 1);
    if (underwater) {
        // Whole-frame wobble, kept subtler than a first pass would since
        // clarity (not murk) is the goal here - Bloop's own release notes
        // describe their underwater work as "clearer and richer... rich
        // reflective surfaces" rather than a dark/muddy look.
        float t = frameTimeCounter;
        vec2 distortion = vec2(
            sin(uv.y * 45.0 + t * 1.7) * 0.5 + sin(uv.y * 13.0 - t * 0.9) * 0.5,
            cos(uv.x * 40.0 + t * 1.3) * 0.5 + cos(uv.x * 17.0 + t * 1.1) * 0.5
        ) * 0.0022 * UNDERWATER_DISTORTION;
        uv += distortion;
    }

    vec3 color = texture2D(colortex0, uv).rgb;

    // Defensive guard against stray NaN/Inf pixels from any upstream
    // divide-by-zero edge case.
    bool bad = (color.r != color.r) || (color.g != color.g) || (color.b != color.b)
             || (abs(color.r) > 1e6) || (abs(color.g) > 1e6) || (abs(color.b) > 1e6);
    if (bad) {
        color = vec3(0.0);
    }

    color *= EXPOSURE;
    color = acesFilm(color);
    color = colorGrade(color);

    if (underwater) {
        // Lighter blue-green tint (clarity, not murk) + a brighter,
        // more defined drifting caustic shimmer.
        color = mix(color, color * vec3(0.55, 0.88, 0.95), 0.5);

        vec2 causticUV = uv * 9.0 + vec2(frameTimeCounter * 0.35, frameTimeCounter * 0.22);
        float caustic = valueNoise3D(vec3(causticUV, frameTimeCounter * 0.15));
        caustic = pow(smoothstep(0.4, 0.9, caustic), 2.0);
        color += vec3(0.10, 0.20, 0.20) * caustic * 0.7 * CAUSTICS_STRENGTH;

        color *= 0.92; // mild dimming, not a heavy murk
    }

    // Vignette (a bit tighter underwater, not a heavy dark ring)
    vec2 vc = texcoord - 0.5;
    float vigStrength = underwater ? VIGNETTE_STRENGTH * 1.5 : VIGNETTE_STRENGTH;
    float vig = 1.0 - dot(vc, vc) * vigStrength * 1.6;
    color *= clamp(vig, 0.0, 1.0);

    // Dither to remove banding in the final 8-bit framebuffer.
    float dither = (bayer4(gl_FragCoord.xy) - 0.5) / 255.0;
    color += dither;

    gl_FragData[0] = vec4(clamp(color, 0.0, 1.0), 1.0);
}
