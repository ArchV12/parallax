// Airless rocky surface (moons, asteroids) — impact craters shaded fully
// per-pixel rather than relying on vertex-color interpolation across a
// low-poly icosphere. A saturated crater field can have well over a hundred
// craters, most too small for the mesh itself to resolve geometrically at a
// sane vertex budget; recomputing the SAME crater math analytically per
// pixel (rather than approximating it from a handful of nearby vertex
// colors) gives crisp rims/walls regardless of mesh resolution. Geometry
// displacement is untouched — this only replaces how the surface is SHADED.
//
// crater_signal()/crater_profile() below are a direct GLSL port of
// CraterField.gd's height_at()/_profile() (minus the depth scaling — see
// crater_signal's comment) — keep the two in sync if either changes.
// MAX_CRATERS must match the array size MoonGenerator.gd passes in.
//
// Displacement is purely radial (CraterField/base noise only scale a unit
// sphere direction, never rotate it), so normalize(model-space VERTEX)
// exactly recovers the original undisplaced sphere direction CraterField
// was evaluated against on the CPU — no separate UV/varying needed to carry
// that direction through.
shader_type spatial;

#include "res://shaders/noise3d.gdshaderinc"

#define MAX_CRATERS 400

uniform vec3 crater_centers[MAX_CRATERS];
uniform float crater_radii[MAX_CRATERS];
// Per-crater freshness (0 = ancient/eroded, 1 = pristine). Scales the whole
// profile — the SAME amp CraterField.height_at() applies to geometry — so old
// craters are faint soft depressions with no bright rim, and only fresh ones
// get the crisp rim + highlight. This is the fix for the "bright-rimmed bubble
// field" look where every crater read as equally new.
uniform float crater_freshness[MAX_CRATERS];
uniform int crater_count = 0;

uniform vec4 color_dark : source_color = vec4(0.15, 0.14, 0.13, 1.0);
uniform vec4 color_mid : source_color = vec4(0.35, 0.33, 0.31, 1.0);
uniform vec4 color_light : source_color = vec4(0.6, 0.58, 0.55, 1.0);

// Surface texture is TWO layers at very different scales — one alone can't
// work at every viewing distance:
//   - mottle: large soft FBM patches (the maria/highland-style albedo
//     variation you can see on the real Moon from Earth) — this is what
//     keeps the surface from reading as flat sand at a distance, where
//     per-grain speckle averages out to nothing.
//   - grain: fine per-cell speckle for close-up regolith roughness.
uniform float mottle_scale : hint_range(1.0, 16.0) = 5.0;
uniform float mottle_strength : hint_range(0.0, 0.6) = 0.35;
uniform float grain_scale : hint_range(20.0, 800.0) = 260.0;
uniform float grain_strength : hint_range(0.0, 0.5) = 0.18;
// How much brighter a crater's raised rim reads versus the surrounding
// terrain — driven by the exact analytic profile, so it stays a crisp ring
// no matter how coarse the underlying mesh is. Kept subtle: the palette
// ramp below ALREADY lightens rims (positive profile pushes toward
// color_light), so this stacks multiplicatively on top of that — at 0.35
// the combination read as hard-drawn white outlines around every crater.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
uniform float seed_offset = 0.0;

varying vec3 v_obj_pos;

void vertex() {
	v_obj_pos = VERTEX;
}

// x = chordal distance / crater radius. Bowl floor -> rising wall -> raised
// rim -> smooth falloff — must match CraterField._profile() exactly.
float crater_profile(float x) {
	if (x >= 1.25) {
		return 0.0;
	}
	if (x >= 1.0) {
		return mix(0.35, 0.0, smoothstep(1.0, 1.25, x));
	}
	if (x >= 0.85) {
		return mix(-0.2, 0.35, smoothstep(0.85, 1.0, x));
	}
	return mix(-1.0, -0.2, smoothstep(0.0, 0.85, x));
}

// Craters apply in ARRAY ORDER, each overwriting whatever is beneath its
// footprint, fading out over the outer falloff annulus — must match
// CraterField.height_at()'s stratigraphic-overwrite rule exactly (see the
// comment there for why it isn't a sum, and why the old magnitude-based
// "strongest wins" rule painted spiky star/sliver artifacts wherever a rim
// crossed another crater's bowl). Returns the raw PROFILE value (-1 bowl
// floor .. 0.35 rim peak .. 0 untouched terrain), NOT scaled by crater
// depth like the CPU height — shading works in profile units throughout
// (see fragment()), so bowls and rims span the full palette no matter how
// physically shallow the geometry displacement is. Squared-distance
// early-out mirrors CraterField.height_at(): the sqrt only runs for the
// few craters actually within reach, not all MAX_CRATERS every pixel.
float crater_signal(vec3 dir) {
	float h = 0.0;
	for (int i = 0; i < crater_count; i++) {
		float radius = crater_radii[i];
		float max_reach = radius * 1.25;
		vec3 dv = dir - crater_centers[i];
		float d2 = dot(dv, dv);
		if (d2 > max_reach * max_reach) {
			continue;
		}
		float x = sqrt(d2) / radius;
		float influence = 1.0 - smoothstep(1.0, 1.25, x);
		// Identical amp to CraterField.height_at(): old craters shade faintly
		// (small profile → palette stays near the flat mid, rim highlight below
		// never fires), fresh ones get the full bowl-to-bright-rim range.
		float amp = mix(0.25, 1.0, crater_freshness[i]);
		h = mix(h, crater_profile(x) * amp, influence);
	}
	return h;
}

void fragment() {
	vec3 dir = normalize(v_obj_pos);
	// Craters only, unlike MoonGenerator.gd's CPU-side _height_at() (which
	// also adds a small base FBM ripple for geometry). Deliberate: that
	// ripple is tiny (surface_roughness ~0.02) and porting FastNoiseLite's
	// exact simplex noise here wouldn't line up with the CPU-displaced
	// geometry pixel-for-pixel anyway. The grain speckle below fills the
	// same "not perfectly smooth" role for non-crater terrain instead.
	float p = crater_signal(dir);

	// Map profile units onto the palette with flat terrain pinned at the
	// midpoint: bowl floor (-1) -> 0 (dark), untouched (0) -> 0.5 (mid),
	// rim peak (0.35) -> ~0.7 (gently toward light — earlier passes mapped
	// the peak at 1.0 and then 0.85 and both still read as bright painted
	// outlines around every crater; bowls keep the full ramp to dark because
	// depth contrast is what sells the craters, but rims only need a hint of
	// lift since the rim_strength highlight below stacks on top). NOT the
	// old CPU vertex-color formula ((h + 0.25) / 0.35 on the depth-scaled
	// height) — that squeezed the whole realistic height range into
	// t ≈ [0.5, 0.8], so bowls never got anywhere near the dark end of the
	// palette and everything rendered as closely-spaced mid-tones: the
	// "airbrushed clay" look this shader exists to fix.
	float t = p < 0.0 ? (p + 1.0) * 0.5 : 0.5 + p * 0.6;
	vec3 col = mix(color_dark.rgb, color_mid.rgb, smoothstep(0.0, 0.5, t));
	col = mix(col, color_light.rgb, smoothstep(0.5, 1.0, t));

	// Both texture layers sample the UNIT direction, not v_obj_pos —
	// model-space position is radius-scaled, and the same body renders at
	// wildly different display radii (Forge preview ~0.35 units vs Cockpit
	// moons ~4.0), so position-based sampling would change the apparent
	// texture scale ~10x between views of the identical moon.
	// fbm3's output clusters tightly around 0.5 (five 0..1 value-noise
	// octaves at halving amplitudes — typical deviation only ~±0.15), so a
	// raw (fbm - 0.5) * strength mottle was nearly invisible: single-digit
	// percent brightness variation, reading as uniform sand at a distance.
	// Stretch the broad band to double contrast, and layer a second band at
	// 4x frequency (half weight) so there's visible structure at mid
	// viewing distances too, not just a few wide patches from far away.
	vec3 off = vec3(seed_offset * 0.73, seed_offset * 0.41, seed_offset * 0.59);
	float mottle = (fbm3(dir * mottle_scale + off) - 0.5) * 2.0
			+ (fbm3(dir * mottle_scale * 4.0 + off + 17.0) - 0.5);
	col *= 1.0 + mottle * mottle_strength;
	float grain = hash13(floor(dir * grain_scale) + seed_offset);
	col *= 1.0 + (grain - 0.5) * grain_strength;

	// Rim highlight: crater_profile() peaks at 0.35 right at the rim (x in
	// [0.85, 1.0]) before falling back to 0 past it — thresholding high in
	// that range isolates just the rim ring, not the whole raised lip.
	// Thresholds are in profile units, which is what crater_signal returns;
	// an earlier version thresholded the depth-scaled height here, which
	// capped at 0.35 * crater_depth ≈ 0.02 — permanently below 0.20, so the
	// highlight silently never fired at all.
	float rim = smoothstep(0.20, 0.32, p);
	col = mix(col, col * (1.0 + rim_strength), rim);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
