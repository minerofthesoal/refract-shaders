# Refract Shaders

Formerly **Aurora Shaders**. Renamed for this overhaul - same underlying
engine (still v17-derived), new name because it's grown well past what
"Aurora" originally described, and because the pack's two signature
features - light refracting/bending through water and through colored
glass - are what it's actually built around now.

## v22.3.0: Nether & End dimension shaders, Modrinth publish fixes

### Added
- **Nether dimension shaders** (`shaders/world-1/`): a dedicated `composite.fsh`
  for the Nether. Drops the overworld's godrays/sun-glare, volumetric clouds,
  and wet-reflection puddles (none of that makes sense without a visible sun
  or rain), adds a low warm ember ambient floor so fully unlit caverns read
  as dim glow instead of crushed black, and adds a lava-vision effect
  (heat-shimmer + tint) for `isEyeInWater == 2` - nothing in the pack handled
  the camera being submerged in lava before.
- **End dimension shaders** (`shaders/world1/`): a dedicated `composite.fsh`
  for the End. Drops overworld clouds (vanilla never spawns clouds there,
  and the pack's cloud code would otherwise draw them straight over the
  void through the open sky above the islands) and rain-dependent effects,
  keeps a re-tinted volumetric light shaft using the End's fixed
  (non-day/night-cycling) light direction for a stable beam-through-the-void
  look, and adds a constant violet void-mist ground haze.
- **Biome-aware ambient/horizon/sun colors** (`lib/common.glsl`):
  `getAmbientSkyColor()`, `getHorizonSkyColor()`, and `getSunColor()` now
  branch on the existing `biome_category` uniform (`CAT_NETHER`,
  `CAT_THE_END`) instead of always running through the overworld day/night
  mix. `worldTime` keeps advancing in the background even in dimensions with
  no visible sun, so without this, terrain/water ambient and the composite
  horizon-haze blend would slowly cycle through overworld colors that have
  nothing to do with what's on screen - most visible in the End, where
  `has_skylight = true` means that ambient term isn't zeroed out by a lack of
  sky light the way it incidentally is in the Nether.
- **`package.sh`**: zips `shaders/` and `CHANGELOG.md` with `shaders/` at the
  root of the archive, for manual uploads to Modrinth/CurseForge or dropping
  straight into `.minecraft/shaderpacks/`.

### Fixed
- **Modrinth publish workflow failing on every run:** the JSON metadata sent
  to `POST /v2/version` was missing the `dependencies` field. It's required
  by the v2 API's `CreatableVersion` schema even when empty - Modrinth can't
  tell "no dependencies" from "field never sent" - so every publish attempt
  was rejected with `400 invalid_input`. Also added a `User-Agent` header
  (required per Modrinth's API docs) and made the step print the actual
  response body and HTTP status on failure instead of just failing silently.
- **"No Iris/OptiFine shader folder found" on manual Modrinth upload:** this
  wasn't a Modrinth-side bug - it's caused by zipping the repo folder itself
  (or using GitHub's Code -> Download ZIP button, which wraps everything in
  a `refract-shaders-main/` folder) instead of zipping `shaders/` at the
  archive root. Modrinth looks for `shaders/` directly inside the zip; a
  wrapping folder hides it. `package.sh` (above) produces a correctly
  structured zip every time. The CI workflow's own zip step was already
  structured correctly (`actions/checkout@v4` checks out to the job's
  working-directory root, not a nested folder), so this only ever affected
  manual uploads.
- Corrected a changelog inaccuracy from v22.2.18 below: the Modrinth publish
  step has always been a hand-rolled `curl` call against the v2 API, not the
  `Modrinth/minotaur@v2` GitHub Action.

## v22.2.18: GitHub Modrinth Publishing, Vulkan/VulkanMod compatibility, Sun Box Fix, Better Clouds & Shadows

### Added
- **GitHub Action workflow for publishing to Modrinth** (`.github/workflows/publish-modrinth.yml`): Automatically packages the shader pack `.zip` and uploads release versions to Modrinth on git tag push (`v*`) or manual workflow dispatch.


### Fixed
- **Sun Quad White Box Artifact:** Fixed a bug where `depthtex0` depth values recorded from the sun quad geometry caused `isSky` to evaluate to `false` specifically over the sun quad area, creating a sharp square boundary in volumetric cloud masking, atmospheric fog, and sun glare. `isSky` now samples `depthtex1` (the opaque-only depth buffer) which correctly classifies open sky and sun/moon quads uniformly.
- **Vulkan / VulkanMod Renderer Compatibility:**
  - Added preprocessor guards around `GL_ARB_shader_texture_lod` to prevent SPIR-V compilation errors on Vulkan compilers.
  - Standardized fragment render target outputs across all passes to `gl_FragData[0]`.
  - Added explicit depth and color buffer declarations (`shadowMapFormat = DEPTH24`, `shadowColor0Format = RGBA8`, `shadowColor1Format = RGBA8`) to `shaders.properties` for proper VulkanMod render target initialization.

### Improved
- **Better Volumetric Clouds:**
  - Integrated **Beer-Lambert Light Attenuation** ($e^{-d \cdot \text{density}}$) and **Powder-Sugar Effect** ($1 - e^{-3.5 \cdot \text{density}}$) for dense, realistic cloud cores and glowing edges.
  - Added **Dual-Lobe Henyey-Greenstein Scattering** ($g_1=0.65, g_2=-0.30$) for realistic forward/backward sunlight scatter.
  - Added high-frequency detail billow noise for fluffy, organic cumulus cloud structures.
- **Better Shadows:**
  - Upgraded PCSS contact-hardening penumbra calculation in `sampleShadowPCF` with dithered Poisson disc sampling for smooth, noise-free soft shadow falloffs.
  - Refined `screenSpaceSunShadow` to include depth thickness thresholding and distance-faded contact shadow rendering for crisp contact under block edges, feet, and foliage.


## Round 13: the moon's real box bug, glare that respects occlusion, safer ocean color, night fog

### Fixed
- **The actual cause of the box/plane artifact around the sun and moon.**
  Round 12 targeted a bloom mip-sampling theory for this, which was a
  real (and worth keeping) fix, but not the main cause - a screenshot
  of the moon at night showing a large, hard-edged diagonal plane made
  the real bug obvious: the Round 10 moon fix trusted the real texture's
  own alpha channel to shape the visible disc, on the assumption that
  vanilla's `moon_phases.png` encodes each phase's crescent/gibbous
  cutout there. It doesn't reliably do that - the texture's alpha reads
  as effectively opaque across its *entire* square tile, not just the
  visible disc, so the shape mask was landing near 1.0 everywhere: a
  solid glowing square, not a moon-shaped glow, which is exactly what a
  hard-edged box/plane in the sky looks like once picked up by bloom at
  a grazing angle. Back to a real geometric circular falloff (the
  technique the sun already used successfully and was never affected
  by this) to actually constrain the shape; the real texture's color
  still supplies phase/surface detail within that boundary.
- **The sun/moon's glow didn't respect occlusion by terrain.**
  `computeSunGlare` only ever checked whether the *current pixel* was
  sky, never whether the light source itself was actually visible from
  the camera - so standing where the sun or moon sat behind a mountain
  still showed the full glow on every open-sky pixel nearby, since nothing
  checked whether the source itself was in view. Now samples the depth
  buffer at the light source's own projected screen position (a small
  soft-edged cluster of samples, not a single hard point, so it doesn't
  visibly pop as the light crosses behind a branch or cloud edge) and
  fades the glow out when the source itself is blocked.

### Changed
- **Ocean temperature differentiation, done safely this time.** Round
  12 pulled this back to almost nothing after the round-11 version's
  unbounded math turned water blood red. Reintroduced real warm/cold
  differentiation, but built entirely out of `mix()` toward fixed
  target colors (which can't leave the range between its two inputs,
  unlike the extrapolation that caused the red-water bug) - reads
  vColor's own green-vs-blue balance, which vanilla genuinely does vary
  between warm/lukewarm and cold ocean water colors, rather than
  `temperature`, which doesn't. `vColor` is now passed into
  `getOceanTemperatureTint` explicitly as a parameter instead of
  assumed as an in-scope global, since `common.glsl` is included before
  the calling shader's own `varying vec4 vColor` declaration.
- **Swamp water reflectivity** (Round 12) and the moonlit/dusk cloud
  rim-lighting and billowing (Round 12) are unchanged this round.

### Added
- **Night atmospheric fog** (`NIGHT_FOG_STRENGTH`): a light, noise-
  driven ground haze at night, independent of the regular distance fog
  - real moonlit mist isn't a flat function of distance, it drifts in
  patches and sits thickest near the ground, so this samples a slow-
  moving noise field for density and thins out with height above the
  ground instead.

### Notes for testing
The moon fix in this round replaces a "trust the texture" approach with
a "trust known-working geometry" approach specifically because the
former turned out to be an untested assumption about texture data - a
good reminder that sourcing a value from "the real texture" doesn't
automatically make it more correct if what's actually in that texture
was never verified.

## Round 12: a critical ocean-color bug, box-around-the-sun, more reactive clouds, and an honest look at Voxy

### Fixed
- **Cold/warm ocean water turning blood red.** Critical regression from
  Round 11's own ocean-temperature fix. That version pushed color via
  `result = baseColor + (baseColor - neutral) * 0.8` - a linear
  extrapolation, not a blend. At typical ocean depth, `baseColor` sits
  close to `deepTint` (a dark navy blue), which is far from the
  assumed "neutral" reference in every channel; extrapolating away
  from it drove R, G, *and* B all negative at once. Nothing downstream
  clamps color before it reaches bloom/tonemap, and running negative
  values through that math is exactly what was turning ocean water
  red instead of blue - a much worse failure than the "does nothing"
  bug it replaced. Rewritten with a plain `mix()` toward a fixed
  target color for the one case that's actually correct (frozen_ocean,
  confirmed via `temperature`), which by construction can never leave
  the range between its two inputs. No longer tries to invent a signal
  for separating warm/lukewarm/cold apart, since there isn't a
  reliable one available - see Round 11's note on MC-240396. Real per-
  biome variation still comes through via `vColor`, upstream of this
  function, same as before.
- **Box-shaped artifact around the sun.** Traced to bloom's mip-chain
  sampling (`composite2.fsh`): a single direct sample at a coarse mip
  level (mip 5 averages a 32x32 block of the original screen per
  texel) can show that mip's own texel grid as a hard rectangular edge
  when a small, very bright source - the sun - sits mostly within one
  or two of those texels. This is a known failure mode of simple
  "sample the raw mip chain" bloom. Fixed with a small tent filter (5
  bilinear taps per mip instead of 1), which is the standard fix -
  forces interpolation across neighboring texels of that mip instead
  of ever reading one flat. Also explicitly forced linear filtering on
  the bloom buffer (`colortex2Nearest = false`) as cheap insurance
  against the same failure mode from a different angle.
- **Swamp water washed out to a pale haze instead of reading murky.**
  Real turbid/algae water scatters light diffusely rather than
  mirroring the sky the way clear water does; without accounting for
  that, a bright or overcast sky (swamp's usual weather) reflected
  strongly enough to wash the Round 10 murk color back out. Swamp
  water's fresnel reflectivity is now dampened, scaled by the same
  `SWAMP_MURKINESS` setting.

### Changed
- **Clouds now react more visibly to sunrise/sunset**, not just the
  moon: the same edge-rim lighting technique added for moonlit clouds
  in Round 10 is now also applied using the sun's own (already warm/
  HDR at dusk) color, gated to peak near sunrise/sunset - real
  golden-hour clouds catch a dramatic rim light along their sun-facing
  edges well beyond what the base color mix alone produces.
- **Clouds billow instead of only drifting.** Added a slow, independent
  vertical drift to the noise sampling (separate from the existing
  horizontal wind translation), so the cloud shapes themselves slowly
  evolve over time rather than a fixed pattern just sliding sideways
  at constant speed.

### On Voxy compatibility - an honest update
I looked into this properly this time, including Voxy's own GitHub
issue tracker, and want to be straight about what I found rather than
claiming a fix that isn't real: **meaningful Voxy/Iris shader
compatibility isn't something achievable by editing a shaderpack's own
GLSL source.** Voxy's LOD geometry is injected into the render pipeline
by Voxy's own Java-side renderer (see `IrisVoxyRenderPipeline.java`,
`VoxyRenderSystem.java` in its source), not by anything a shaderpack
writes to. The actual gaps reported by users on Voxy's own tracker -
LOD chunks not receiving the same lighting as regular chunks, water
losing its color behind real geometry, distant water not fading
correctly - are described there as problems with how *Voxy* writes into
Iris's g-buffers, not anything downstream in a shader's own code. One
maintainer comment on a recent issue put it plainly: "shader support is
pretty much nonexistent for quite a while." A formal request for the
specific things a shader would need from Voxy (correct depth/normal
g-buffer injection so effects like SSR and volumetric lighting apply to
LOD terrain) is still open and unresolved as of this writing (voxy#500).

What that means here: this pack already processes whatever fragments
it receives the same way regardless of whether vanilla or Voxy produced
them (nothing in `gbuffers_terrain.fsh` assumes vanilla-only geometry),
and the distance-handling changes from Round 10/11 (`VOXY_COMPAT`) are
genuinely useful regardless. But if Voxy's own LOD chunks currently
render unlit, unshadowed, or with broken water at a distance, that's
this pack correctly rendering whatever Voxy handed it - the fix for
that lives in Voxy, not here. I'd rather say that clearly than keep
making shader-side changes that can't actually reach the real problem.

### Notes for testing
The ocean color bug in particular is a good reminder to sanity-check
"does this formula ever produce something outside 0..1 or negative"
for anything feeding into a color, not just whether the visible result
looks reasonable at the one depth/angle it happened to get eyeballed
at.

## Round 11: fixing Round 10's own regressions, plus night ambient

Testing after Round 10 turned up real problems in several of that
round's own changes - this round is entirely about fixing those, not
new work. Documented plainly since some of these are "the previous
fix was wrong," not "here's an improvement."

### Fixed
- **Ocean temperature tint still did nothing** (`getOceanTemperatureTint`
  in `common.glsl`). Round 10's version was built on a wrong assumption:
  that Iris's `temperature` uniform differs across ocean variants the
  way their names suggest. It doesn't - confirmed against Mojang bug
  report MC-240396, a long-standing, documented vanilla quirk: every
  ocean variant except `frozen_ocean` reports the exact same internal
  temperature (0.5). `cold_ocean` and plain `ocean` were being pushed
  by an identical amount, which is exactly why they looked the same in
  testing. Rewritten to exaggerate the water's own real per-biome color
  (`vColor`, already blended in) around a neutral midpoint instead -
  that data actually does differ per biome. `temperature` is still used
  for the one thing it's genuinely correct about (frozen_ocean really
  is 0.0 vs. 0.5 everywhere else), for an extra icy push specifically
  there.
- **Glowing water edges, worst at night.** Traced to the new underwater
  light-shaft feature calling `computeGodRays()` a second time with the
  same arguments as the scene's regular god-ray pass immediately above
  it - a full extra shadow-map raymarch recomputing the same value, then
  tinted and boosted 1.8x on top of the pass already added to `color`
  once. A shadow-map raymarch is especially prone to artifacts right at
  a depth discontinuity, and a small water surface's own silhouette
  against the surrounding terrain is exactly that - doubling and
  boosting that raymarch's contribution there is what was reading as a
  bright halo hugging the water's edges (far more visible at night
  against a dark backdrop, which is why it stood out most there even
  though the underlying bug wasn't actually night-specific). Now reuses
  the single already-computed god-ray value instead of a second march,
  at a much more modest strength (1.8x -> 0.5x).
- **Lava turned into a wrinkled-foil/crumpled-fabric texture.** The real
  cause wasn't the new noise octave from Round 10 (that was a
  reasonable first guess, dialed back as a precaution but wasn't the
  main problem) - it was that the lava color line was multiplying the
  raw animated texture sample's full RGB directly into the final color,
  on top of a *separate*, already-correct luma-based modulation two
  lines earlier. That redundant full-color multiply had always been
  there in some form, but Round 9/10's mip-bias fix (forcing sampling
  back to full mip-0 sharpness to stop cross-tile atlas bleed) removed
  the automatic blurring that had been incidentally hiding it, which is
  what turned "a bit noisy" into "visibly wrinkled." Dropped the
  redundant RGB multiply - the procedural hotspot/vein pattern is the
  only color driver now, with just brightness (not full color)
  modulated by the real texture's fine detail, as the code's own
  comments already claimed it was doing.
- **Voxy compatibility change made fog worse for everyone, Voxy or
  not.** Round 10 floored the far-fog anchor to 2200+ blocks whenever
  `VOXY_COMPAT` was on - which defaults on for everyone, not just Voxy
  users. For a normal player with a normal (100-400 block) render
  distance, that floor sat completely outside anything ever actually
  visible, silently removing the backstop atmospheric fade this pack
  otherwise relies on, rather than just not mattering the way it was
  reasoned through at the time. Reverted that specific change; the
  anchor is back to scaling purely off the player's own `far`, which is
  correct for the common case and doesn't pretend to know how far Voxy
  is actually rendering clearly at any given moment.
  `VOXY_COMPAT` still does something real: it now smoothly fades out
  (rather than hard-cutting) close-range-only effects - ambient
  occlusion and screen-space contact shadows - past 96-128 blocks,
  since sub-block detail is meaningless at LoD viewing distance and a
  hard pop at a fixed distance is its own minor visual bug for anyone
  with a large render distance, Voxy or not.
  **Honest note:** beyond the above, I don't have enough specifics to
  know what "doesn't work with Voxy" refers to - a screenshot of the
  actual broken behavior (Voxy terrain rendering black/unlit, a hard
  seam, a crash, etc.) would make it possible to target the real issue
  instead of guessing at more changes blind.

### Changed
- **Non-true-black night ambient brightened and re-hued.** Both
  `NIGHT_DARKNESS` 0 and 1 (1 is the default) are noticeably brighter
  now and pushed further toward a richer moonlit blue-violet instead of
  a flatter dark gray-blue, in the ambient light, the horizon gradient,
  and the sky's own zenith/horizon colors together (previously only
  some of these were touched at a time, which could read as an
  inconsistent mood between the sky and the ground). `NIGHT_DARKNESS`
  2 ("very dark") and `TRUE_BLACK_NIGHTS` are both left exactly as they
  were - those are the intentionally-darker opt-ins and weren't part of
  what was reported as too dark/flat.

### Notes for testing
Same caveat as every round: none of this has been run in an actual
Minecraft + Iris session. The lava and water-edge fixes in particular
came from reading the code closely enough to find a genuinely wrong
line each time (not just retuning numbers), which is a good sign, but
"the logic is now correct" and "it looks right in-game" aren't always
the same thing until it's actually seen rendered.

## Round 10: swamp water, moon, forest shadows, ocean identity, Voxy, five new features

### Fixed
- **Swamp water reading as clear/blue instead of murky green.** The
  biome color blend was real (vanilla's own dark swamp water color was
  genuinely being sampled via `vColor`), but two other things were
  washing it out: this pack's water is built around a "crystal clear,
  see the seabed" look (extended `WATER_CLARITY` + a low 0.22 alpha
  floor, same for every biome), and swamp water is almost always
  shallow, so `depthFactor` rarely climbed high enough for the biome-
  tinted color to dominate over the barely-tinted raw texture. Added a
  dedicated, steeper murk ramp and opacity floor for `CAT_SWAMP`
  specifically (`SWAMP_MURKINESS` setting), instead of making the whole
  pack's water less clear to compensate.
- **Lava still slightly bugged after Round 9.** Found a real leftover
  mismatch: the mip-bias comment always claimed `-4.0` (intended to
  force sampling back to the base mip regardless of how far `churn`
  had drifted the UV) but the code actually applied `-1.5`, which
  still let automatic LOD selection drift up a mip and bleed across
  neighboring atlas tiles at the noise's steepest points - the
  remaining faceted/cross-tile shimmer traced straight back to this.
  Also added a third, higher-frequency detail octave to lava's hotspot
  noise and widened the crust/vein transition band, since a small
  1-2 block pool was barely sampling any variation across the two
  existing broad-scale octaves and read as one smooth gradient blob
  rather than a churning, cracked surface.
- **Moon reading as a shapeless blue haze instead of a visible phase
  disc.** A synthetic circular alpha mask (built from distance to the
  tile center) was taking `max()` against, and in practice fighting,
  the real moon-phase texture's own alpha - which already encodes each
  phase's actual crescent/gibbous shape as real art. At most phases
  the synthetic circle let large parts of the texture's "dark" side
  through as if they were part of the lit sliver, which is what read
  as a mostly featureless glow. Now trusts the texture's own alpha for
  the disc completely, and only uses the distance-based falloff for an
  *additive* halo drawn around/outside it - the halo can add glow but
  can never suppress or reshape the real phase art.
- **Beach/sunset overexposure.** Traced to two compounding things, not
  sand albedo (already addressed in Round 8): the dusk sun-glare halo's
  radius/brightness curve (`computeSunGlare`) grew wide and bright
  enough at peak dusk that, seen through the many small gaps in a tree
  canopy near the sun's screen position, it blew out a large fraction
  of the frame instead of staying a contained golden-hour glow; and
  bloom's mip weighting (`composite2.fsh`) put nearly a third of its
  energy into the two widest, most-downsampled mips, smearing any
  strong compact source across a correspondingly huge screen area.
  Pulled the dusk halo's growth in and retuned the bloom weights toward
  the tighter mips (weights still sum to 1.0).
- **Forests/jungles reading flatly lit despite a visible canopy
  overhead.** The existing colored-shadow mechanism tints light through
  leaves but barely darkens it (leaves intentionally write a fainter
  tint alpha than glass, then get run through `GLASS_SKYLIGHT_STRENGTH`'s
  own gentle glass-tuned curve on top - measured out to roughly 10%
  darkening under a solid leaf block). Added a new, independent canopy
  occlusion term (`translucentCanopyOcclusion` in `common.glsl`,
  `FOLIAGE_SHADOW_STRENGTH` setting) that reuses the existing PCF
  shadow kernel a second time against `shadowtex0` (all casters) versus
  `shadowtex1` (opaque only) - their difference is a real, already-
  antialiased canopy density estimate, with no new render target or
  per-material bookkeeping needed. Wired into terrain, water, and
  entities.

### Added
- **Ocean biomes look more distinct and reflect their temperature.**
  `getOceanTemperatureTint()` in `common.glsl` uses Iris's real
  `temperature` uniform to push warm/lukewarm oceans further toward
  turquoise/tropical and cold/frozen oceans further toward pale icy
  blue-white, layered on top of (not replacing) the existing per-biome
  `vColor` blend so the two reinforce each other. `OCEAN_TEMPERATURE_TINT`
  setting.
- **Dynamic colored-glass shadow spread** (`GLASS_BLEED_DYNAMIC_SPREAD`,
  `GLASS_BLEED_DUSK_MULTIPLIER`): the colored-light bleed radius now
  widens automatically as the sun approaches sunrise/sunset, like real
  low-angle light scattering further across a room - a shaft of
  golden-hour light through a window lights up much more floor than
  the same window does at noon.
- **Voxy LoD mod compatibility pass** (`VOXY_COMPAT` setting). Voxy
  renders its own simplified terrain far past vanilla's `far` distance
  using its own draw calls, without changing what the `far` uniform
  itself reports - so the existing far-fog anchor (already Voxy-aware
  since an earlier round, but only ever a multiple of `far`) would
  still fog out Voxy's extended terrain at vanilla-scale distance,
  undermining the entire point of running it. The anchor is now floored
  to a large fixed distance instead when `VOXY_COMPAT` is on, so the
  actual distance-based atmospheric density term (already unbounded)
  does the real fading work at any range. Also skips SSAO and screen-
  space contact shadows past 128 blocks - sub-block detail that's
  meaningless at LoD-scale viewing distance and otherwise wasted
  GPU time marching against simplified geometry. Note: Voxy's own
  shader-support mechanism (per its GitHub issues/community docs)
  patches compatible packs on load and isn't fully documented
  publicly; this pass targets everything that's actually specified
  (the LoD depth/normal writes it needs are already correct, since
  this pack sticks to standard gbuffer conventions) rather than
  guessing at undocumented protocol details.
- **Five new features:**
  - **Underwater volumetric light shafts** - reuses the existing
    god-ray shadow-map raymarch with its own cooler, caustic-rippled
    tuning while the eye is submerged (`UNDERWATER_GODRAYS_STRENGTH`).
  - **Foliage backlight** - thin leaves/grass glow when the sun sits
    behind them instead of only ever reading as flat-lit
    (`FOLIAGE_BACKLIGHT_STRENGTH`).
  - **Fireflies** - drifting glow-points over forest/jungle/swamp/taiga
    ground at night (`FIREFLIES`, `FIREFLY_STRENGTH`).
  - **Snow/ice sparkle** - a sparse, narrow-lobe specular glint field
    on snow and ice, reading as light catching individual crystal
    facets as the camera moves (`SNOW_SPARKLE_STRENGTH`; new
    `block.10104` tag).
  - **Aurora borealis** - drifting color-shifting ribbons over cold
    biomes at night, gated on Iris's real `temperature` uniform rather
    than a single biome category so it covers taiga/icy/snowy/frozen-
    coast biomes together (`AURORA`, `AURORA_STRENGTH`).
- **Beautiful nighttime clouds** (doesn't count against the five above,
  per request): added a moonlit rim-light/silver-sheen term
  (`NIGHT_CLOUD_GLOW`) so clouds stay visibly shaped and dramatic
  against the night sky instead of fading to a near-flat gray haze
  once the sun's own day/night brightness scalar bottoms out.

### Notes for testing
As with every round: none of this has been run in an actual Minecraft
+ Iris session, since that's outside what's available here. The lava
and moon fixes in particular are the kind of thing that's easy to
reason through correctly on paper and still look slightly different
in practice than intended - screenshot the results (day and night, a
few biomes, a swamp pond, and a real Voxy session if you have one
installed) and it'll be much faster to zero in on anything still off
from there than to keep guessing blind.

## Round 9: lava (the actual bug this time)

### Fixed
- **Lava's diagonal stripe/interference pattern - the real cause.**
  Both `churn` and `lavaFlicker` were calling `hash13()` directly on
  smoothly-varying continuous world position, not on a floored lattice
  point the way every other noise call in this pack (correctly) does.
  hash13 is only designed to look random when sampled at discrete
  integer points; fed a continuous sweep instead, its first internal
  step (`fract(p * 0.1031)`) is essentially a sawtooth wave with a
  ~9.7-unit period per axis, and two of those combining is exactly what
  produces a diagonal interference pattern. This was a genuinely
  different, more fundamental bug than the mip-bias and coordinate-
  precision issues fixed in earlier rounds - neither of those touched
  this code path, which is why the pattern persisted (in a different
  shape) even after both fixes. Replaced both hash13 calls with
  valueNoise3D, which does the floor+interpolate correctly.

## Round 8: sun, lava (real root cause), biome color identity

### Added
- **Real per-biome color grading**, using Iris's actual `biome_category`
  uniform (`CAT_JUNGLE`, `CAT_DESERT`, `CAT_TAIGA`, `CAT_SWAMP`,
  `CAT_OCEAN`, `CAT_ICY`, `CAT_SAVANNA`, `CAT_MESA`, `CAT_MUSHROOM`,
  `CAT_THE_END`, `CAT_NETHER`) rather than an approximation faked from
  vertex colors - confirmed this uniform is genuinely provided by Iris
  (not OptiFine-only) before building on it. Applies a full-screen
  color temperature nudge + saturation adjustment per biome category in
  `colorGrade()` (`final.fsh`), on top of (not replacing) the existing
  per-block vColor tinting in `gbuffers_terrain.fsh` - vColor tinting
  covers grass/foliage/water on a block-by-block basis, this covers
  everything else (stone, sky, fog, the whole view) so an entire biome
  carries a bit of its own mood. Deliberately kept gentle throughout.

### Fixed
- **Sun rendering as a hard-edged glowing quad instead of a soft round
  disc.** The corona falloff reached all the way to the sun quad's own
  edge (edgeDist 1.0); even at very low opacity there, that thin band
  around the full quad boundary was bright enough to bloom into a
  visible glowing outline matching the underlying geometry's own
  (perspective-skewed) silhouette. Pulled the falloff in well short of
  the quad's edge.
- **Lava moire pattern - actual root cause found.** Two prior attempts
  (mip bias, then a screen-space-derivative fade for grazing angles)
  helped but didn't fully fix it, because the real cause was different:
  the noise driving lava's hotspot pattern was fed raw absolute world
  coordinates, which get large (thousands of blocks) far from spawn.
  Hash-based noise loses meaningful precision at that magnitude, and
  for a hash function that shows up as chaotic output rather than a
  graceful quality drop - exactly the fine ring pattern reported, and
  why it showed up on close, direct views too, not just grazing ones.
  Wrapping the coordinate into a bounded range before it reaches the
  noise fixes this at the source.
- **Desert/sand reading as overexposed.** `softenHighlights()` was only
  ever applied to incoming *light*, not to light-times-albedo. Sand's
  albedo is high enough (~85-90% reflectance) that already-softened
  light could still multiply back into overexposed territory once
  applied to such a bright surface. Added a second softening pass after
  the albedo multiply.
- **Ocean biome water all reading the same color regardless of
  temperature.** Verified against the actual game data first (vanilla's
  warm/lukewarm/cold/frozen oceans do have genuinely different water
  colors, delivered through the same per-vertex color mechanism as
  grass) - the bug wasn't missing data, it was in how it was used. The
  water gradient's shallow/mid/deep base colors are fixed aesthetic
  values, and multiplying them by the biome color's hue alone wasn't
  enough to meaningfully shift an already strongly-colored base.
  Blending toward the biome color's actual RGB (not just its
  hue-normalized direction) for the shallow/mid range gives real
  separation between ocean types; deep water stays close to the fixed
  dark base, matching how real water converges toward uniform darkness
  at depth regardless of surface biome.
- **Taiga/spruce grass reading as dull.** Added a saturation boost on
  the per-biome vertex color tint, weighted inversely to how saturated
  it already is - already-vivid biomes (jungle, swamp) see little to no
  change, muted ones (taiga, badlands) get pushed further from gray.
  Untinted blocks (stone, sand) are unaffected since their vColor sits
  at/near white already.

## Round 7: ice misclassification, profile button

### Fixed
- **Ice was included in `isWater`'s blockId range** (`< 10102.0`
  instead of `< 10101.0`), so it silently got the full water treatment
  - vertex wave displacement included. Water's displacement only holds
  together because contiguous water shares matching per-vertex offsets;
  an isolated ice block bordering ordinary terrain has nothing matching
  to meet at its edges, tearing a sharp gap open there. Narrowed the
  range so ice now correctly falls through to the (flat, undisplaced)
  glass branch instead.
- **No way to actually reach the profile system in-game.**
  `profile.Potato/Lemon/Mid/High/Ultra` had real values but produced no
  UI - per Iris's docs, a literal `<profile>` token has to be added to
  a `screen` list for a profile button to appear, and it never was.
  Added to the front of the main screen list.

## Round 6: first in-engine testing - SSR and refraction fixes

v22 (glass reflection/refraction + WATER_REFLECTION_MODE + screen-space
contact shadows) was written and reviewed for GLSL correctness but never
actually compiled/rendered before release. This round fixes what showed
up in the first real in-game screenshots.

### Fixed
- **Scrambled/TV-static noise on both water and glass.** The refraction
  UV offset (added this version, sampling colortex3 at
  `screenUV + waveNormal * 0.035ish`) reused a magnitude that was tuned
  for atlas-texture UV space (rippleUV's `texcoord`, a tiny sliver of
  the block texture sheet). Applied to full-screen UV space instead,
  0.035 is 3.5% of the screen's width - tens to 100+ pixels on a real
  display, changing every frame with the wave normal/noise. Every
  water/glass pixel was sampling colortex3 at an essentially incoherent
  point relative to its neighbors. Both offsets (water and glass) now
  scale by `texelSize` instead, so the wobble is a fixed handful of
  actual pixels regardless of resolution.
- **Reflections still noisy at coarser SSR settings.** Coarse march
  steps (as low as 6 on the default Mid profile, and now shared with
  glass on top of water) regularly overshot thin/complex geometry
  before the hit test fired, sampling colortex3 at whatever unrelated
  pixel the overshoot landed on. Added a binary-search refinement pass
  once a hit is detected, converging back toward the actual
  intersection instead of accepting the overshot position.

## Round 5: reference-driven water, sparkle, atmosphere, and sun glare

Based on 9 reference screenshots (crystal-clear tropical water, dramatic
golden-hour god rays, hazy atmospheric mountain vistas, moody true-dark
nights).

### Changed
- **Much clearer water.** The depth-tint ramp now takes roughly twice as
  long to reach its "fully deep" look, and the alpha floor for the
  shallowest water dropped from 0.40 to 0.22 - shallow-to-mid water now
  stays legible enough to read seabed detail several blocks down,
  matching the reference shots, instead of tinting over fairly quickly.
  Added a `WATER_CLARITY` setting to tune how far this extends.
- **Broader sun-glint/sparkle field.** The angular gate controlling
  where sparkle can appear widened substantially (was a tight cone
  right along the exact reflection direction). Deliberately left the
  sparkle points' own size and per-cell activation rate untouched - an
  existing code comment noted a wider version of *those* specifically
  had previously washed out into a flat hazy sheen, so only the angular
  spread changed, keeping individual sparkle points crisp.
- **Earlier, more gradual atmospheric haze.** The far-distance fog blend
  now starts at 40% of render distance instead of 60%, spread over a
  wider band - distant terrain fades into haze gradually across most of
  the visible distance instead of being sharp until the last stretch.
- **Bigger, more dramatic sun glow at golden hour**, plus a new
  stylized radial sunburst-ray effect through the glow (most visible at
  sunrise/sunset, fades out at midday). This is a stand-in for
  atmospheric/lens rays, not a physical simulation, and reads even over
  open sky - unlike the volumetric god rays, which need actual geometry
  in the view ray to show up at all.

## Round 4: SSAO noise fix, glass light bleed + skylight shadow

### Fixed
- **SSAO occasionally produced scattered pure-black pixels** ("black
  noise", separate from the rain issue). Two compounding bugs: (1) the
  occlusion average divided by a *running count of valid samples*
  rather than the fixed sample count, so a pixel where only 1-2 of 8
  samples landed on-screen could read as 100% occluded just because
  those couple happened to hit something; (2) each tap drew a fully
  independent random direction per pixel with no blur pass to clean the
  result back up, which reads as harsh salt-and-pepper noise even
  without bug (1). Fixed the division, and rebuilt sampling around a
  fixed, well-distributed spiral (Vogel disk) in a proper tangent-space
  hemisphere, rotated per pixel by the existing ordered Bayer dither -
  neighboring pixels now get correlated results (a fine, even dither)
  instead of independently random ones.
- Caught and fixed 3 instances of my own typo this session (a stray `#`
  where a `//` should've been in a multi-line comment, which would
  break the preprocessor) before packaging - flagging this here rather
  than not mentioning it. Every file was re-scanned for the same
  pattern afterward; none remain.

### Added
- **Colored light bleed onto nearby blocks.** Previously, colored light
  from stained glass only ever appeared exactly within its own sharp
  shadow silhouette - a wall a couple of blocks to the side of a window
  got nothing at all. A much wider secondary sample of the same
  shadowcolor buffer now lets a reduced-strength version of that tint
  spill onto surfaces just outside the direct shadow shape too, the way
  real light scattered through a window doesn't stop dead at a
  razor-sharp edge.
- **Glass "skylight" shadow.** Glass, leaves, and ice previously only
  recolored direct sunlight passing through them - a stained-glass
  window let 100% of the sun's intensity through, just tinted. Real
  glass loses some light to reflection, and stained glass blocks a
  real fraction of it outright; there's now an actual dimming term
  under any translucent caster, scaled by how strongly tinted that
  caster's own shadowcolor sample reads.
- Both new behaviors are controlled by two new settings in the Shadows
  menu (`GLASS_BLEED_STRENGTH`, `GLASS_SKYLIGHT_STRENGTH`), both with
  tooltips.

### Investigated, no changes needed
- **"Cool Rain" mod compatibility** - checked what the mod actually
  does: it's audio-only (ambient sound effects on blocks during rain,
  varying by distance/material). It doesn't touch rendering or Iris at
  all, so there's nothing for a shader pack to be incompatible with -
  it should already coexist fine with this pack as-is.

## Round 3: rain fix, iGPU presets, cloud volume, water polish

### Fixed
- **Rain rendered as a wall of hard, fully-saturated blue bars** with
  no sense of depth or atmosphere (seen directly in a testing
  screenshot - a forest scene solid with vertical blue streaks).
  Vanilla's own rain texture was being drawn completely untouched.
  Softened base opacity substantially, added a distance fade so the far
  edge of the rain grid dissolves into haze instead of hard-cutting
  off, and added per-column brightness variation so it doesn't read as
  one mechanically uniform, repeating sheet.

### Added
- **Two integrated-graphics profiles** - `iGPU_Dual` (weaker/lower-
  thread-count chips, e.g. an i7-7660U's Iris Plus graphics) and
  `iGPU_Quad` (stronger quad-core/8-thread chips still on integrated
  graphics, e.g. an i7-7700HQ's HD 630). These hard-disable soft
  shadows and SSAO rather than just turning them down - exactly the
  kind of per-pixel branching/multi-sample work integrated GPUs handle
  worst - on top of a much smaller shadow map, shorter shadow/god-ray/
  cloud step counts, and reduced bloom.
- **Real height/volume in the clouds.** The cloud layer is now more
  than twice as thick as before, with a proper height-shaped density
  curve instead of a uniform slab: a comparatively flat, sharp base
  (like the real condensation altitude) and a soft, eroded, "fluffier"
  top that needs progressively denser noise to register the higher up
  it goes. Added a large-scale regional coverage bias too, so clouds
  clump into distinct clustered masses with clear gaps between them
  instead of one uniform ceiling - that clustering is most of what
  actually reads as "real volume" rather than a hazy flat sheet.
- **Biome-tinted water.** The depth-based turquoise-to-deep-blue
  gradient now blends in the actual biome water color (swamp murky
  green, ocean/river blue, etc.) instead of every biome looking
  identical. Applied to both the water surface and underwater/vertical
  water faces.
- **Wave-crest whitecaps** on open water, not just the shoreline foam
  band - driven by the wave normal's own steepness and scaled up with
  how hard it's raining, so choppy weather visibly shows more
  whitecaps.

## Round 2: new features

### Added
- **Wet-ground puddle reflections.** While it's raining, flat/
  upward-facing terrain gets patchy, fresnel-driven screen-space
  reflections - real puddles, not a uniform "everything is shiny" sheen.
  Has to run as a post-process step in `composite.fsh` rather than
  inside `gbuffers_terrain.fsh` directly: at the moment an opaque
  terrain fragment is shaded, nothing else in the scene has been drawn
  into any buffer yet, so there's nothing yet to reflect. This also
  finally makes use of the `wetness` uniform, which was declared but
  completely unused before this pass.
- **Cloud shadows.** Clouds now actually dim direct sunlight on the
  ground/water beneath them as they drift by, instead of being a purely
  sky-only visual with zero effect on ground lighting. A cheap 2D
  single-sample stand-in for the real volumetric clouds (same noise
  coordinate + wind drift, so the shadow shape/position tracks what's
  actually visible in the sky above).
- **Chromatic dispersion.** A subtle prismatic fringe on water
  reflections at grazing angles - a stylized nod to real dispersion
  (different wavelengths bending by slightly different amounts through
  a refractive interface), and a fitting signature touch for a pack
  called *Refract*.
- **Rain ripples.** Animated concentric rings expand and fade across
  water surfaces while it's raining, tiled across a jittered grid so
  many ripples are spawning/aging independently rather than one
  uniform repeating pattern.
- 5 new settings across a new **Weather** options category plus two
  additions to **Water**, all with tooltips in `en_us.lang`.

## Round 1: rename + core fixes

### Fixed
- **Colored shadows through glass were broken for entities.** Mobs and
  players standing under stained glass got plain white light instead of
  tinted light - `gbuffers_entities.fsh` still had the old broken gate
  (`if (shadow < 0.999)`) that `gbuffers_terrain.fsh` and
  `gbuffers_water.fsh` had already been fixed to not use. Brought
  entities in line with terrain/water.
- **Colored light through glass looked like a hard-edged, blocky/
  triangular patch instead of a soft glow** (visible on ceilings/floors
  directly under stained-glass windows). The tint lookup was a single
  unfiltered shadow-map texel, which reproduced the shadow map's own
  texel grid and the glass mesh's triangle edges exactly. Added a
  4-tap filtered lookup (`sampleShadowTintPCF`) so it reads as a soft
  patch of color instead.
- **Shadows popped off abruptly at the shadow render distance edge**
  instead of fading out. Added a smooth fade over the last ~25% of
  `SHADOW_DISTANCE`.
- **Sun/moon glint on water bloomed into one big soft blob** rather
  than a tight sparkle. Added a dedicated glint-strength control
  (defaults toned down from the old effective 1.0) and raised the
  bloom threshold so highlights need to be genuinely bright before
  they start blooming.

### Added
- **Ambient occlusion (SSAO)** - soft contact darkening in corners and
  creases that a single directional shadow map can't produce on its
  own. Toggleable, with strength and quality/sample-count controls.
  Off by default on the Lite profile.
- **Seabed caustics** - a dancing, net-like light pattern visible
  through shallow, sunlit water, fading out with depth and shadow.
- New water controls: reflection strength (how mirror-like at grazing
  angles), foam strength, sun-glint strength, caustics strength,
  underwater screen-distortion strength.
- New bloom threshold control (paired with the existing bloom
  strength).
- `shaders/lang/en_us.lang` - every setting now has a readable name and
  tooltip in the in-game shader options screen instead of just the raw
  macro name.

### Unchanged (still working as before)
- Flat-mesh + per-pixel wave normals for water (no vertex tearing).
- Screen-space reflection for water/glass-adjacent surfaces.
- Volumetric clouds, god rays, sun/moon glare.
- Slope-scaled shadow bias, Poisson-disc PCF, contact-hardening
  blocker search.
- Day/night/dusk color curves, True Black Nights option.

## Notes for testing

This was written and reviewed for GLSL correctness but not compiled or
rendered in-engine on this machine - there's no Minecraft/Iris
available in this environment. Everything was cross-checked for brace/
paren/`#if`-`#endif` balance, malformed preprocessor lines, and every
new function/uniform/setting resolving correctly in every file that
uses it, but please treat the first load as a real test. If Iris
reports a shader compile error, paste the exact error text back and
it'll get fixed immediately - much faster than guessing.

Things worth a look once you're in-game, since none of this could be
visually iterated on here:
- The wet-reflection puddle mask scale/threshold and the AO radius are
  reasonable starting guesses, not tuned against your actual world.
- Cloud shadows use a fixed sample scale matched to the real clouds'
  own coordinates - if the shadow patches look too small/large
  relative to the visible clouds, that's a one-line multiplier tweak.
- Chromatic dispersion is deliberately subtle by default (0.6); turn it
  up in the Water menu if you want it more pronounced.
- The new rain distance-fade range (20-56 blocks) and opacity
  (0.22-0.42) were picked to fix the specific "wall of hard blue bars"
  look from the screenshot - adjust in `gbuffers_weather.fsh` if it now
  reads as too faint/too strong once you can actually see it rendered.
- The two iGPU profiles are tuned by reasoning about what's expensive
  (shadow map size, soft-shadow filtering, SSAO, march step counts),
  not measured on the actual hardware - if either still runs too slow
  or looks worse than it needs to, the values are all in one line each
  in `shaders.properties` (`profile.iGPU_Dual` / `profile.iGPU_Quad`).
