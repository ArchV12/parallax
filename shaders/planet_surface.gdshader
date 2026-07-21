// Per-fragment terrain surface for procedural rocky/water planets.
//
// The icosphere (built + radially displaced on the CPU) supplies only the
// silhouette and macro relief; ALL surface color and micro-detail happen here,
// per pixel. This is the point of the shader: the old path vertex-colored the
// mesh and let Gouraud interpolation blend band colors ACROSS each triangle,
// which smeared coastlines into soft gradients that followed triangle edges.
// Applying the height→color ramp per fragment instead makes the sea/land line
// pixel-sharp, and a high-frequency detail noise both jitters that line into a
// natural coast and perturbs the normal for close-up micro-relief the geometry
// is far too coarse to carry.
//
// Base (macro) height is baked per vertex on the CPU and passed through UV.x at
// full float precision — displacement is purely radial, so normalize(VERTEX)
// recovers the original unit sphere direction exactly, giving us latitude and a
// stable noise domain that rotates WITH the planet (sampling in world space
// would make the surface swim as the body spins).
shader_type spatial;

#include "res://shaders/noise3d.gdshaderinc"

// Palette — fed from PlanetGenerator._make_palette. source_color so Godot does
// the sRGB→linear conversion, matching how the colors were authored.
uniform vec4 shallow_color : source_color = vec4(0.2, 0.4, 0.55, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.08, 0.18, 1.0);
uniform vec4 beach_color : source_color = vec4(0.8, 0.75, 0.55, 1.0);
uniform vec4 lowland_color : source_color = vec4(0.3, 0.45, 0.25, 1.0);
uniform vec4 highland_color : source_color = vec4(0.45, 0.4, 0.3, 1.0);
uniform vec4 mountain_color : source_color = vec4(0.35, 0.32, 0.3, 1.0);
uniform vec4 snow_color : source_color = vec4(0.92, 0.93, 0.96, 1.0);

uniform float sea = 0.0;           // sea level in noise-height units
uniform float noise_max = 0.75;    // practical max of the FBM height field
uniform bool has_caps = true;
uniform float cap_start = 0.8;     // latitude (|y| + altitude bias) where snow begins

// Detail layer. detail_freq is applied to the unit direction, so feature size
// is independent of planet radius. detail_strength nudges the band lookup so
// coastlines/biome edges wander instead of tracing the interpolated macro
// height; bump_strength tilts the normal for micro-relief shading.
uniform float detail_freq = 9.0;
uniform float detail_strength = 0.04;   // band-lookup jitter — breaks flat single-band expanses
uniform float albedo_variation = 0.45;  // light/dark mottle WITHIN a band — the "texture"
uniform float bump_strength = 0.7;
uniform float seed_offset = 0.0;   // per-planet noise offset, from the seed

varying vec3 v_local_pos;
varying float v_base_h;

void vertex() {
	v_local_pos = VERTEX;
	v_base_h = UV.x;
}

// Two-scale surface detail centered on 0 (~[-0.75, 0.75]). The broad octave
// interleaves bands and shades macro relief; the finer octave (added at a third
// the weight) is what gives close-up grain. One function so the albedo mottle
// and the normal bump read from exactly the same field.
float surf_detail(vec3 p) {
	return (fbm3(p) - 0.5) + (fbm3(p * 3.7 + 19.1) - 0.5) * 0.4;
}

// Height → color: a direct port of the old GDScript _height_color ramp, now
// evaluated per pixel. smoothstep windows collapse the original branch guards
// (mountain/snow blends are already zero below their onset).
vec3 height_color(float h, vec3 dir, float d) {
	vec3 col;
	if (h < sea) {
		float depth = clamp((sea - h) / (sea + noise_max + 0.001), 0.0, 1.0);
		col = mix(shallow_color.rgb, deep_color.rgb, sqrt(depth));
	} else if (h < sea + 0.03) {
		col = beach_color.rgb;
	} else {
		float t = clamp((h - sea) / max(noise_max - sea, 0.001), 0.0, 1.0);
		// Real FBM height rarely nears noise_max, so a lowland→highland ramp
		// that finishes at t=0.75 leaves almost all land sitting on the pale,
		// desaturated highland end (the washed-out look). Delaying the crossover
		// keeps the saturated lowland color across most of the actual range.
		col = mix(lowland_color.rgb, highland_color.rgb, smoothstep(0.15, 0.95, t));
		col = mix(col, mountain_color.rgb, smoothstep(0.7, 1.0, t));
	}
	// Polar caps: altitude pushes the snow line toward the equator so peaks
	// whiten before lowlands at the same latitude. The detail term breaks the
	// snow line into a natural coast rather than a smooth latitude ring — a
	// clean-edged cap creeping down the disc is a big part of the "white ball"
	// read. Sea stays uncapped (ice is the ocean's job, not the land ramp's).
	if (has_caps && h >= sea) {
		float lat = abs(dir.y) + max(h - sea, 0.0) * 0.25 + d * 0.15;
		col = mix(col, snow_color.rgb, smoothstep(cap_start, cap_start + 0.1, lat));
	}
	return col;
}

void fragment() {
	vec3 dir = normalize(v_local_pos);           // unit sphere direction (== original vertex)
	vec3 np = dir * detail_freq + vec3(seed_offset);

	// Warp the sample domain ONCE (reused by the value read and the finite-diff
	// gradient below) so terrain detail doesn't quilt along the value-noise
	// grid. Doing it here rather than inside surf_detail keeps it to 3 extra
	// fbm3 evals total instead of 3 per gradient sample.
	vec3 warp = vec3(
		fbm3(np + vec3(1.7, 9.2, 4.3)),
		fbm3(np + vec3(8.3, 2.8, 5.1)),
		fbm3(np + vec3(3.1, 6.4, 7.9))) - 0.5;
	vec3 wp = np + warp * 0.8;

	float d = surf_detail(wp);
	// Jitter the band lookup so a single band doesn't paint a flat expanse, then
	// pick the band color.
	float h = v_base_h + d * detail_strength;
	vec3 col = height_color(h, dir, d);

	// The key fix for flat-paint surfaces: mottle brightness WITHIN the band so
	// terrain reads as textured ground rather than one uniform tone.
	col *= clamp(1.0 + d * albedo_variation, 0.0, 2.0);

	ALBEDO = col;
	ROUGHNESS = 0.95;

	// Normal bump from the same detail field (one-sided differences). Project
	// the gradient onto the tangent plane so it only tilts the normal, then
	// carry it into view space (where NORMAL lives). MODELVIEW_MATRIX is
	// vertex-only in Godot 4; VIEW_MATRIX * MODEL_MATRIX is the fragment-stage
	// equivalent (both are uniform-scale here, so directions transform cleanly).
	float eps = 0.3;
	vec3 grad = vec3(
		surf_detail(wp + vec3(eps, 0.0, 0.0)) - d,
		surf_detail(wp + vec3(0.0, eps, 0.0)) - d,
		surf_detail(wp + vec3(0.0, 0.0, eps)) - d) / eps;
	grad -= dir * dot(grad, dir);
	vec3 grad_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(grad, 0.0)).xyz;
	NORMAL = normalize(NORMAL - grad_view * bump_strength);
}
