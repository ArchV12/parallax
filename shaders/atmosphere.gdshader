// Atmosphere/corona shell driven by view-ray path length: for each pixel, how
// much shell does the ray traverse (minus what the planet blocks)? This
// yields the physical limb profile — faint haze over the disc, a bright band
// at the limb, and a smooth fade to nothing at the shell's outer edge (no
// hard circle). Also doubles as a star's corona: self_luminous skips the
// day-side dimming, since a star has no dark side — it IS the light source.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 atmo_color : source_color = vec4(0.45, 0.65, 1.0, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.5;
// Higher = glow hugs the limb tightly; lower = spreads toward the shell edge.
uniform float falloff : hint_range(0.5, 3.0) = 1.5;
uniform float planet_radius = 1.0;
uniform float shell_radius = 1.1;
// World-space direction from the planet toward the sun. Unused when
// self_luminous is true.
uniform vec3 sun_dir = vec3(0.4, 0.3, 0.85);
uniform bool self_luminous = false;

void fragment() {
	vec3 frag_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(frag_world - CAMERA_POSITION_WORLD);
	vec3 to_center = NODE_POSITION_WORLD - CAMERA_POSITION_WORLD;
	// Closest approach of the view ray to the planet center; b is the ray's
	// miss distance ("impact parameter").
	vec3 closest = CAMERA_POSITION_WORLD + rd * dot(to_center, rd);
	float b = length(closest - NODE_POSITION_WORLD);

	float outer_half = sqrt(max(shell_radius * shell_radius - b * b, 0.0));
	float inner_half = sqrt(max(planet_radius * planet_radius - b * b, 0.0));
	// Rays hitting the planet keep only the front half-chord (the far half is
	// behind the surface); rays grazing past it keep the full chord, which
	// shrinks to zero at the shell edge.
	float path = (b >= planet_radius) ? 2.0 * outer_half : outer_half - inner_half;
	float max_path = 2.0 * sqrt(max(shell_radius * shell_radius - planet_radius * planet_radius, 0.0001));
	float glow = pow(path / max_path, falloff);

	// Day-side factor with a soft wrap past the terminator, based on where
	// the ray passes the planet, so it works beyond the limb too. A star's
	// corona has no day side — it glows uniformly from every angle.
	float day = 1.0;
	if (!self_luminous) {
		vec3 n = normalize(closest - NODE_POSITION_WORLD);
		day = clamp(dot(n, normalize(sun_dir)) * 0.6 + 0.45, 0.05, 1.0);
	}

	ALBEDO = atmo_color.rgb * glow * density * 1.4 * day;
}
