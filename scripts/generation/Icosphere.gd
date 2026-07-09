class_name Icosphere
extends RefCounted

# Shared icosphere builder — subdivided icosahedron with fully shared
# vertices (no UV seams). Any generator needing a seamless sphere mesh with
# smooth per-vertex displacement (planets, moons, asteroids...) uses this
# instead of its own copy, so a fix like the winding correction below only
# ever has to happen in one place.

static func build(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v: Vector3 in [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]:
		verts.append(v.normalized())

	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	for level in subdivisions:
		var midpoint_cache: Dictionary = {}
		var new_faces: Array = []
		for face: Array in faces:
			var a: int = face[0]
			var b: int = face[1]
			var c: int = face[2]
			var ab := _midpoint(a, b, verts, midpoint_cache)
			var bc := _midpoint(b, c, verts, midpoint_cache)
			var ca := _midpoint(c, a, verts, midpoint_cache)
			new_faces.append([a, ab, ca])
			new_faces.append([b, bc, ab])
			new_faces.append([c, ca, bc])
			new_faces.append([ab, bc, ca])
		faces = new_faces

	var packed_verts := PackedVector3Array(verts)
	var indices := PackedInt32Array()
	indices.resize(faces.size() * 3)
	var i := 0
	# The classic icosahedron face table is counter-clockwise (OpenGL front);
	# Godot front faces are clockwise — emit each triangle flipped, otherwise
	# the mesh renders inside-out (near side culled, far side interior
	# visible) and normals point inward.
	for face: Array in faces:
		indices[i] = face[0]
		indices[i + 1] = face[2]
		indices[i + 2] = face[1]
		i += 3
	return [packed_verts, indices]


static func _midpoint(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var key: int = (mini(a, b) << 32) | maxi(a, b)
	if cache.has(key):
		return cache[key]
	var idx := verts.size()
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = idx
	return idx
