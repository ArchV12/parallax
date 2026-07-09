class_name RingSystem
extends RefCounted

# Shared ring-mesh builder — a flat annulus lying in the body's equatorial
# plane (XZ, matching the Y-axis "latitude" convention the gas/ice giant band
# shader already uses for its poles). Any generator whose body can have a
# ring system uses this instead of its own copy.

const RING_SHADER := preload("res://shaders/ring.gdshader")

static func build(rng: RandomNumberGenerator, body_radius: float, amount: float, tint: Color) -> MeshInstance3D:
	var inner: float = body_radius * 1.3
	var outer: float = body_radius * (1.9 + amount * 1.1)  # denser rings extend further out

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	mat.set_shader_parameter("density", amount)
	mat.set_shader_parameter("ring_color", tint)

	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = _build_annulus(inner, outer)
	mi.material_override = mat
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
