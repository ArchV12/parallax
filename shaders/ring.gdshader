// Planetary ring — a flat, semi-transparent annulus divided into a fixed
// number of discrete concentric tracks (track_count): Uranus's real rings
// read as essentially one narrow track with empty space either side; real
// Saturn has a dozen or so major divisions packed close enough to look
// near-solid. At track_count = 1 the radial coordinate is used as-is (a
// single track has no "spacing" to make organic); above that, the boundary
// positions themselves are domain-warped by low-frequency noise before
// splitting into periods, so real ring systems' hallmark — wildly uneven
// band/gap widths, not a mechanically even barcode — falls out naturally.
// Each track also gets its own brightness jitter, not just width, so some
// bands read as fainter/thinner than others.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/noise3d.gdshaderinc"

uniform float seed_offset = 0.0;
uniform int track_count : hint_range(1, 14) = 5;
uniform vec4 ring_color : source_color = vec4(0.8, 0.75, 0.65, 1.0);

void fragment() {
	float r = UV.x;  // 0 at inner edge, 1 at outer edge

	// Warp strength ramps in above 1 track and saturates by ~6 — a single
	// track stays exactly as clean as before, since there's nothing to
	// unevenly space with only one band.
	float warp_strength = smoothstep(1.0, 6.0, float(track_count)) * 0.4;
	float warp = (fbm3(vec3(r * 4.0 + seed_offset, seed_offset * 0.3, 0.0)) - 0.5)
			* warp_strength / float(track_count);
	float r_warped = clamp(r + warp, 0.0, 1.0);

	float t = r_warped * float(track_count);
	float idx = floor(t);
	float local = fract(t);
	float idx_hash = fract(sin((idx + seed_offset) * 12.9898) * 43758.5453);
	float idx_hash2 = fract(sin((idx + seed_offset) * 78.233) * 12543.867);
	float width = mix(0.45, 0.85, idx_hash);
	float half_w = width * 0.5;
	float track = smoothstep(0.5 - half_w, 0.5 - half_w + 0.08, local)
			* smoothstep(0.5 + half_w, 0.5 + half_w - 0.08, local);
	// Some bands read as fainter/thinner-looking than others, same as real
	// ring photos — not just varying width.
	float track_brightness = mix(0.5, 1.0, idx_hash2);

	// Fine noise so a track reads as textured ice/rock, not a flat bar.
	float grain = fbm3(vec3(r * 60.0 + seed_offset, seed_offset * 0.5, 0.0));

	// Fades in from the inner edge and out at the outer edge instead of
	// stopping abruptly — real ring systems taper, they don't have a hard wall.
	float edge_fade = smoothstep(0.0, 0.06, r) * smoothstep(1.0, 0.94, r);
	float alpha = track * track_brightness * edge_fade * clamp(grain * 0.5 + 0.6, 0.0, 1.0);

	ALBEDO = ring_color.rgb * mix(0.75, 1.15, grain);
	ALPHA = alpha;
}
