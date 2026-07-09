// Star surface — self-luminous plasma, not a lit rocky surface. Unshaded and
// emissive so the star looks the same from every angle: it has no day/night
// side, because it IS the light source, not something lit by one.
//
// Two independent noise layers, both sampled seamlessly in 3D (see
// noise3d.gdshaderinc): fine, fast granulation (convective mottling) and a
// coarser, sparser layer thresholded into sunspots.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/noise3d.gdshaderinc"

uniform float seed_offset = 0.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.4;
uniform float spot_activity : hint_range(0.0, 1.0) = 0.15;
uniform vec4 star_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 spot_color : source_color = vec4(0.35, 0.12, 0.05, 1.0);

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(v_dir);
	vec3 p = dir * 3.0 + vec3(seed_offset * 0.73, seed_offset * 0.41, seed_offset * 0.59);

	// Granulation: fine mottled turbulence over the whole surface, brightening
	// and darkening the base color slightly — the "boiling plasma" look.
	float grain = fbm3(p * 6.0) - 0.5;
	vec3 col = star_color.rgb * (1.0 + grain * turbulence * 0.6);

	// Sunspots: sparse, larger dark blotches from a coarser noise layer.
	// Higher activity lowers the threshold (more spots) as well as the
	// coverage multiplier.
	float spots = fbm3(p * 1.6 + 50.0);
	float spot_thr = mix(0.95, 0.6, spot_activity);
	float spot_mask = smoothstep(spot_thr, spot_thr + 0.05, spots) * min(spot_activity * 2.0, 1.0);
	col = mix(col, spot_color.rgb, spot_mask);

	ALBEDO = col;
	EMISSION = col * 1.4;
}
