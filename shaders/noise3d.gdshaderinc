// Shared seeded 3D value-noise/FBM for shaders that sample noise on a
// sphere's surface direction (model-space vertex, normalized) rather than in
// UV space — UV.x wraps 0→1 at the meridian and non-periodic noise tears
// there as a seam, while a direction vector has none by construction.
// Used by gas_giant.gdshader and star_surface.gdshader.

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// Quintic fade (Perlin's improved curve), not the cubic f*f*(3-2f): cubic is
	// only C1, so the noise GRADIENT has slope-kinks at every cell boundary,
	// which show up as quilted facet seams wherever the field drives a normal
	// bump. Quintic is C2 → smooth gradients, no seams. Value is near-identical
	// mid-cell, so existing users (gas giant, star, moon) shift imperceptibly.
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += amp * value_noise3(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

// Domain-warped fbm3: displace the sample by a low-frequency noise vector so
// value noise's axis-aligned grid — blocky threshold contours (cloud edges),
// straight-line seams — bends into organic swirls. `warp` ~0.3-0.8 is a light
// nudge; larger scrambles the pattern. Costs 3 extra fbm3 evaluations.
float fbm3_warped(vec3 p, float warp) {
	vec3 q = vec3(
		fbm3(p + vec3(1.7, 9.2, 4.3)),
		fbm3(p + vec3(8.3, 2.8, 5.1)),
		fbm3(p + vec3(3.1, 6.4, 7.9))) - 0.5;
	return fbm3(p + q * warp);
}
