// Planetary ring — a flat, semi-transparent annulus with radial banding and
// gaps (the real Saturn's rings have dozens, the Cassini Division being the
// most famous). Alpha and tint vary along the radius via the shared 3D FBM,
// sampled with radius as one axis so bands run concentrically.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/noise3d.gdshaderinc"

uniform float seed_offset = 0.0;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform vec4 ring_color : source_color = vec4(0.8, 0.75, 0.65, 1.0);

void fragment() {
	float r = UV.x;  // 0 at inner edge, 1 at outer edge

	// Fine bands plus a coarser gap layer at a different frequency, so gaps
	// don't line up with band edges in a suspiciously regular way.
	float bands = fbm3(vec3(r * 40.0 + seed_offset, seed_offset * 0.5, 0.0));
	float gaps = fbm3(vec3(r * 9.0 + seed_offset * 1.7, 5.0, 0.0));

	// Density fades in from the inner edge and out at the outer edge instead
	// of stopping abruptly — real ring systems taper, they don't have a hard
	// wall.
	float edge_fade = smoothstep(0.0, 0.06, r) * smoothstep(1.0, 0.94, r);
	float gap_mask = smoothstep(0.3, 0.5, gaps);
	float alpha = clamp(bands * 0.6 + 0.3, 0.0, 1.0) * edge_fade * gap_mask * density;

	ALBEDO = ring_color.rgb * mix(0.7, 1.1, bands);
	ALPHA = alpha;
}
