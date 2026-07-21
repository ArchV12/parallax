// Translucent cloud shell for procedural planets — a thin sphere just above the
// surface (below the atmosphere shell). Coverage is fbm3 sampled on the unit
// direction (no UV seam) and thresholded into distinct masses with clear gaps;
// coverage raises/lowers that threshold. The shader is LIT (not unshaded), so
// the scene's directional light gives the cloud deck the same day/night
// terminator as the ground beneath it.
//
// Sampling is in local space so cloud patterns rotate with the planet, plus a
// slow TIME-driven longitude drift so the deck creeps relative to the surface
// the way real weather does — independent of whatever spins the mesh.
shader_type spatial;
render_mode cull_back, depth_draw_never;

#include "res://shaders/noise3d.gdshaderinc"

uniform vec4 cloud_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_freq = 3.0;
uniform float drift_speed = 0.01;
uniform float seed_offset = 0.0;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 dir = normalize(v_local_pos);

	// Slow drift about the spin axis (Y).
	float a = TIME * drift_speed;
	float ca = cos(a);
	float sa = sin(a);
	dir.xz = mat2(vec2(ca, -sa), vec2(sa, ca)) * dir.xz;

	vec3 np = dir * cloud_freq + vec3(seed_offset);
	// Broad masses (domain-warped so the coverage threshold doesn't cut along
	// the noise grid into square-edged blobs) shaped by a finer wispy layer.
	float c = fbm3_warped(np, 0.6) * 0.7 + fbm3(np * 2.7 + 13.1) * 0.3;

	// Higher coverage lowers the threshold → more sky filled. The soft
	// smoothstep window keeps cloud edges feathered rather than hard-cut.
	float thresh = mix(0.72, 0.34, coverage);
	float cov = smoothstep(thresh, thresh + 0.14, c);

	ALBEDO = cloud_color.rgb;
	ALPHA = cov * cloud_color.a;
}
