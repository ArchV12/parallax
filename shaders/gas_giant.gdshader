// Procedural gas/ice giant bands.
//
// All noise is sampled in 3D on the sphere's surface direction (model-space
// vertex, normalized) — NOT in UV space. UV.x wraps 0→1 at the meridian and
// non-periodic noise tears there as a vertical seam; a direction vector has
// no seam by construction.
//
// Band color uses a triangle wave (abs(fract*2-1)), not fract() — the sawtooth
// jump of fract() draws a hard line at every band boundary, while the triangle
// wave ping-pongs the gradient a→b→c→b→a continuously.
//
// seed_offset is computed once in GDScript from the planet's seed and fed in
// as a uniform — the shader itself has no RNG, so this is what keeps the
// pattern fully deterministic per seed.
shader_type spatial;

#include "res://shaders/noise3d.gdshaderinc"

uniform float seed_offset = 0.0;
uniform float band_scale : hint_range(0.3, 4.0) = 1.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.4;
uniform float storminess : hint_range(0.0, 1.0) = 0.35;
// 0 = flat/featureless (Uranus, Neptune), 1 = full banding (Jupiter, Saturn).
uniform float band_contrast : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color_a : source_color = vec4(0.85, 0.7, 0.5, 1.0);
uniform vec4 color_b : source_color = vec4(0.65, 0.45, 0.3, 1.0);
uniform vec4 color_c : source_color = vec4(0.45, 0.3, 0.22, 1.0);
uniform vec4 storm_color : source_color = vec4(0.9, 0.55, 0.35, 1.0);

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(v_dir);
	vec3 base = dir * 2.5;
	// Seed offset stays small and is added AFTER frequency scaling — large
	// offsets multiplied through band_scale and five octave doublings push
	// coordinates into float ranges where fract() quantizes, which renders
	// as a blocky patchwork.
	vec3 off = vec3(seed_offset * 0.73, seed_offset * 0.41, seed_offset * 0.59);

	// Anisotropic sampling (tighter in y) elongates the warp horizontally so
	// bands wave and curl along their length rather than crumbling.
	float warp = fbm3(base * vec3(1.5, 3.5, 1.5) * band_scale + off) - 0.5;
	float lat = dir.y * band_scale * 5.0 + warp * turbulence * 1.6;
	float t = abs(fract(lat) * 2.0 - 1.0);  // continuous triangle wave

	vec3 banded = mix(color_a.rgb, color_b.rgb, smoothstep(0.1, 0.55, t));
	banded = mix(banded, color_c.rgb, smoothstep(0.55, 0.95, t));
	// Uranus/Neptune-style worlds: bands are physically there but nearly
	// invisible. Blending toward the flat mid-tone (rather than hiding the
	// band computation) keeps a faint hint of structure instead of a
	// perfectly uniform sphere, which would look like a rendering error.
	vec3 col = mix(color_b.rgb, banded, band_contrast);

	// Storm blotches, also horizontally elongated. Higher storminess lowers
	// the threshold (more storms) as well as deepening the tint.
	float storms = fbm3(base * vec3(3.0, 7.0, 3.0) + off + 41.7);
	float thr = mix(0.75, 0.55, storminess);
	float storm_mask = smoothstep(thr, thr + 0.12, storms) * min(storminess * 1.5, 1.0);
	col = mix(col, storm_color.rgb, storm_mask);

	// Limb darkening — the signature look of a gas giant (cf. any Jupiter
	// photo): the cloud deck runs to the edge and dims at grazing angles
	// where the view passes through more haze. The gas IS the planet; this
	// replaces the need for a separate atmosphere shell.
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	col *= mix(0.45, 1.0, pow(ndv, 0.4));

	ALBEDO = col;
	ROUGHNESS = 0.75;
}
