// Comet tail — a tapered, wispy, glowing cone. The node this is applied to
// is oriented by the viewer (CosmicForge, later the game) to always point
// away from the star; the shader itself only cares about its own local
// length/circumference.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

#include "res://shaders/noise3d.gdshaderinc"

uniform float seed_offset = 0.0;
uniform vec4 tail_color : source_color = vec4(0.6, 0.75, 1.0, 1.0);

const float TAU_C = 6.28318530718;

void fragment() {
	// Sample via sin/cos of the angle rather than UV.x directly — UV.x wraps
	// 0→1 at the same seam CylinderMesh's circumference does, and raw UV
	// noise tears there (same bug already fixed once on the gas giant shader).
	float theta = UV.x * TAU_C;
	vec3 p = vec3(cos(theta) * 2.0, sin(theta) * 2.0, UV.y * 4.0 + seed_offset);
	float wisp = fbm3(p);

	// Alpha peaks near the nucleus end (UV.y = 0) and fades toward the tip.
	float along = UV.y;
	float fade = pow(clamp(1.0 - along, 0.0, 1.0), 1.4);
	float alpha = fade * clamp(wisp * 0.9 + 0.35, 0.0, 1.0);

	ALBEDO = tail_color.rgb;
	ALPHA = alpha;
}
