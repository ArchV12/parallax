class_name RingSystem
extends RefCounted

# Shared ring-mesh builder — a flat annulus, built lying in the XZ plane
# (matching the Y-axis "latitude" convention the gas/ice giant band shader
# already uses for its poles) and then tilted off horizontal, so real ring
# systems' visible axial tilt isn't always a flat top-down disc. Any
# generator whose body can have a ring system uses this instead of its own
# copy.

const RING_SHADER := preload("res://shaders/ring.gdshader")

# extent (0-1): how wide the ring system is, scaling continuously from a
# hairline at 0 up to a full Saturn-style span at 1 — the whole width comes
# from extent (inner edge is fixed), so there's no large fixed baseline
# width forcing every nonzero value to already look thick.
# track_count: how many discrete concentric bands make up the ring —
# Uranus's real rings read as essentially one narrow track, Saturn's as
# dozens packed close enough to look like a near-solid disc.
# tilt_degrees: axial tilt of the ring plane off horizontal, tilted toward a
# random compass direction — real rings are equatorial, so this is really
# standing in for the body's own axial tilt without needing to tilt the
# whole body. -1 (the default) rolls a plausible random tilt from rng
# instead — pass an explicit angle for a known/curated body (e.g. Saturn's
# real 26.7°) so it isn't left to chance.
static func build(rng: RandomNumberGenerator, body_radius: float, extent: float,
		track_count: int, tint: Color, tilt_degrees: float = -1.0) -> MeshInstance3D:
	var inner: float = body_radius * 1.3
	var outer: float = inner + body_radius * 1.7 * extent

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	mat.set_shader_parameter("track_count", track_count)
	mat.set_shader_parameter("ring_color", tint)

	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = _build_annulus(inner, outer)
	mi.material_override = mat

	var tilt: float = tilt_degrees if tilt_degrees >= 0.0 else rng.randf_range(5.0, 45.0)
	var tilt_facing := rng.randf_range(0.0, TAU)  # which compass direction the tilt leans
	mi.transform.basis = Basis(Vector3.UP, tilt_facing) * Basis(Vector3.RIGHT, deg_to_rad(tilt))

	return mi


static func _build_annulus(inner: float, outer: float) -> ArrayMesh:
	const SEGMENTS := 128
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a0 := (float(i) / SEGMENTS) * TAU
		var a1 := (float(i + 1) / SEGMENTS) * TAU
		var dir0 := Vector3(cos(a0), 0.0, sin(a0))
		var dir1 := Vector3(cos(a1), 0.0, sin(a1))

		var p_in0 := dir0 * inner
		var p_out0 := dir0 * outer
		var p_in1 := dir1 * inner
		var p_out1 := dir1 * outer

		# UV.x = normalized radial distance (0 inner edge, 1 outer edge) — the
		# shader reads this for banding/gaps.
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p_in0)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p_out0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p_out1)

		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p_in0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p_out1)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p_in1)
	st.generate_normals()
	return st.commit()
