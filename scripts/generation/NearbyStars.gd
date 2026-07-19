class_name NearbyStars
extends RefCounted

# Real nearest-neighbor stars to Sol — curated the same "known bodies aren't
# rolled" way KnownBodies.gd curates the Sol system itself (see the
# parallax-universe-generation-architecture memory): real name, real
# distance, real spectral type, real sky position. A 2037 setting means
# humanity already has real astronomical data on its neighbors even before
# ever visiting one, same logic that made Sol itself fully pre-known.
#
# Stellar View's board data ONLY (2026-07-18, first step toward a second
# travelable system — see the "order of things" design chat) — no orbits,
# no planets, nothing else yet. Distance is LIGHT-YEARS, not AU
# (KnownBodies' unit) — a wholly different scale, deliberately not reusing
# that class's Entry shape or folding into its Sol-only catalog.
#
# 2026-07-18, revised same day: Stellar View moved from a flat 2D board
# (arbitrary per-star angle) to a real 3D scene, so position_ly() now
# derives genuine 3D placement from real right ascension/declination
# (approximate real-world values, not scientifically precise, but real
# relative sky positions — not invented) instead of a seeded hash angle.
# Standard equatorial-to-Cartesian conversion, remapped to Godot's Y-up
# convention (declination, the "how far north/south" axis, becomes Y;
# right ascension sweeps the X/Z ground plane).
#
# color is a rough real spectral-class tint for the board's star spheres —
# O/B blue-white, A white, F yellow-white, G yellow (Sol's own class), K
# orange, M red. Not photometrically exact, just enough for "redder star
# reads redder on the board."

class Entry:
	var star_name: String = ""
	var distance_ly: float = 0.0
	var spectral_type: String = ""
	var color: Color = Color.WHITE
	var ra_hours: float = 0.0   # right ascension, hours (0-24)
	var dec_deg: float = 0.0    # declination, degrees (-90 to 90)

	# Real 3D position relative to Sol, in light-years — Sol itself is the
	# origin. Godot Y-up: dec -> Y, ra sweeps X/Z.
	func position_ly() -> Vector3:
		var ra_rad := deg_to_rad(ra_hours * 15.0)  # 15 degrees per hour of RA
		var dec_rad := deg_to_rad(dec_deg)
		return Vector3(
			distance_ly * cos(dec_rad) * cos(ra_rad),
			distance_ly * sin(dec_rad),
			-distance_ly * cos(dec_rad) * sin(ra_rad),
		)


static var _catalog: Array[Entry] = []


static func all() -> Array[Entry]:
	_ensure_built()
	return _catalog


static func get_entry(star_name: String) -> Entry:
	for e: Entry in all():
		if e.star_name == star_name:
			return e
	return null


static func _ensure_built() -> void:
	if not _catalog.is_empty():
		return
	# Alpha Centauri A/B and Proxima Centauri really are this close together
	# in both distance AND sky position (Proxima orbits the AB pair at ~0.2
	# ly separation, negligible next to their ~4.3 ly distance from Sol) —
	# the board rendering these three almost on top of each other is
	# accurate, not a layout bug.
	_add("Proxima Centauri", 4.24, "M5.5Ve", Color(0.9, 0.4, 0.3), 14.495, -62.679)
	_add("Alpha Centauri A", 4.37, "G2V", Color(1.0, 0.95, 0.8), 14.660, -60.834)
	_add("Alpha Centauri B", 4.37, "K1V", Color(1.0, 0.8, 0.5), 14.660, -60.837)
	_add("Barnard's Star", 5.96, "M4V", Color(0.9, 0.4, 0.3), 17.963, 4.693)
	_add("Wolf 359", 7.86, "M6V", Color(0.85, 0.35, 0.3), 10.941, 7.015)
	_add("Lalande 21185", 8.31, "M2V", Color(0.9, 0.45, 0.3), 11.056, 35.970)
	_add("Sirius A", 8.66, "A1V", Color(0.75, 0.85, 1.0), 6.752, -16.716)
	_add("Ross 154", 9.68, "M3.5Ve", Color(0.9, 0.4, 0.3), 18.830, -23.836)


static func _add(star_name: String, distance_ly: float, spectral_type: String, color: Color,
		ra_hours: float, dec_deg: float) -> void:
	var e := Entry.new()
	e.star_name = star_name
	e.distance_ly = distance_ly
	e.spectral_type = spectral_type
	e.color = color
	e.ra_hours = ra_hours
	e.dec_deg = dec_deg
	_catalog.append(e)
