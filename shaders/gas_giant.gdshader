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
// Storm feature size: higher = larger, fewer storms (lower sampling frequency).
uniform float storm_scale : hint_range(0.5, 3.0) = 1.5;
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

	float band_phase = dir.y * band_scale * 5.0;

	// Counter-flowing band shear: real belts and zones flow in OPPOSITE
	// directions, and the curls/billows that read as "Jupiter" form at those
	// shear boundaries. sin() over the band coordinate reverses the drift sign
	// every half band (matching the stripe spacing); the east-tangent (-z,0,x)
	// vanishes at the poles by construction (no normalize → no NaN) and peaks
	// at the equator, exactly where the jets are fastest. Offsetting the warp's
	// SAMPLE position by this makes adjacent bands undulate oppositely, so their
	// boundaries curl and churn instead of running parallel. Scales with
	// turbulence, so the knob now drives both waviness and shear.
	float drift = sin(band_phase * TAU);
	vec3 shear_off = vec3(-dir.z, 0.0, dir.x) * drift * turbulence * 0.6;

	// Anisotropic sampling (tighter in y) elongates the warp horizontally so
	// bands wave and curl along their length rather than crumbling.
	float warp = fbm3(base * vec3(1.5, 3.5, 1.5) * band_scale + off + shear_off) - 0.5;
	float lat = band_phase + warp * turbulence * 1.6;
	float t = abs(fract(lat) * 2.0 - 1.0);  // continuous triangle wave

	vec3 banded = mix(color_a.rgb, color_b.rgb, smoothstep(0.1, 0.55, t));
	banded = mix(banded, color_c.rgb, smoothstep(0.55, 0.95, t));
	// Uranus/Neptune-style worlds: bands are physically there but nearly
	// invisible. Blending toward the flat mid-tone (rather than hiding the
	// band computation) keeps a faint hint of structure instead of a
	// perfectly uniform sphere, which would look like a rendering error.
	vec3 col = mix(color_b.rgb, banded, band_contrast);

	// Fine filamentary detail: a high-frequency octave (stretched horizontally
	// like the bands, and dragged along the same shear) mottles brightness
	// WITHIN a band so the cloud deck reads as turbulent gas rather than a
	// smooth color gradient. Amplitude scales with band_contrast so the
	// deliberately featureless ice giants (Uranus/Neptune) stay calm.
	float detail = fbm3(base * vec3(4.0, 12.0, 4.0) * band_scale + off + shear_off * 0.5 + 17.3) - 0.5;
	col *= 1.0 + detail * 0.24 * mix(0.35, 1.0, band_contrast);

	// Storms as discrete belt-aligned vortices. Kept to the HIGH peaks of an
	// elongated fbm (mean ≈ 0.48) so they stay separate ovals — pushing the
	// threshold below the mean, as an intuitive "max storminess = low threshold"
	// mapping does, just floods the whole disc into one connected mass. So the
	// threshold stays in the peak range (0.72→0.60) even maxed; storminess also
	// lifts the fill strength. storm_scale divides the sampling frequency, so a
	// higher value grows the ovals (and thins them out).
	float storm_freq = 1.0 / storm_scale;
	vec3 storm_p = base * vec3(2.5, 5.5, 2.5) * storm_freq + off + 41.7;
	float sf = fbm3(storm_p);

	// Swirl each storm into a vortex: a tangent frame around the local radial
	// (east/north vanish together at the poles → no NaN), with a fine streak
	// noise sampled through coordinates ROTATED by an angle that grows toward
	// the storm core. The swirl domain scales with storm_freq too, so the vortex
	// stays self-similar at any storm size. Fed back into the threshold field so
	// the oval's own EDGES spiral, not just its interior tint.
	vec3 east = vec3(-dir.z, 0.0, dir.x);
	vec3 north = cross(dir, east);
	float core = smoothstep(0.52, 0.72, sf);
	float ang = core * 9.0;
	vec3 swirl_p = base * 5.0 * storm_freq + (east * cos(ang) + north * sin(ang)) * 2.0 * storm_freq + off + 3.1;
	float filament = fbm3(swirl_p) - 0.5;

	float thr = mix(0.72, 0.60, storminess);
	float depth = smoothstep(thr, thr + 0.14, sf + filament * 0.12);  // swirled edges
	// Never a solid opaque fill: cap coverage below 1 and vary it with the swirl
	// so the band beneath shows through and the storm reads as translucent cloud
	// rather than a flat sticker.
	float storm_mask = depth * min(storminess * 1.7, 1.0) * clamp(0.72 + filament, 0.3, 0.9);

	// Rimmed oval: darker collar at the edge (depth≈0.5), filament-textured core.
	// The tint is also slightly desaturated toward its own luminance so it sits
	// in the palette instead of reading as a pure primary.
	float rim = depth * (1.0 - depth) * 4.0;
	float storm_lum = dot(storm_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 storm_tint = mix(storm_color.rgb, vec3(storm_lum), 0.18);
	vec3 storm_col = storm_tint * (1.0 + filament * 0.6) * (1.0 - rim * 0.3);
	col = mix(col, storm_col, storm_mask);

	// Limb darkening — the signature look of a gas giant (cf. any Jupiter
	// photo): the cloud deck runs to the edge and dims at grazing angles
	// where the view passes through more haze. The gas IS the planet; this
	// replaces the need for a separate atmosphere shell.
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	col *= mix(0.45, 1.0, pow(ndv, 0.4));

	ALBEDO = col;
	ROUGHNESS = 0.75;
}
