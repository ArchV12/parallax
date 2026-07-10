class_name KnownBodies
extends RefCounted

# Catalog of curated, known solar-system bodies — the single source of truth
# for facts that never change with context: real relative size (Earth =
# 1.0), real orbital distance (AU from Sol; moons instead set `parent` and
# are positioned by whatever draws them), texture path, and appearance
# (colors, rings, axial tilt). Cosmic Forge's picker, Cockpit's Earth/Luna,
# and System view's orbital map all build their CanonicalBodyParams from
# here instead of each hand-copying the same facts — see "curate what's
# known" in the parallax-universe-generation-architecture memory.
#
# atmosphere/atmo_falloff/radius are DEFAULTS, not fixed facts — callers in
# a close-up context (Cockpit) or a dev-tool slider (Cosmic Forge) may
# reasonably override them for their own framing, same as Cockpit already
# tunes Earth's atmosphere differently than Cosmic Forge's default. Colors,
# texture paths, ring presence, and axial tilt ARE fixed facts and should
# not be overridden per-caller.

class Entry:
	var body_name: String = ""
	var texture_subdir: String = ""
	var fallback_color: Color = Color.WHITE
	var atmo_color: Color = Color.WHITE
	var radius_ratio: float = 1.0    # Earth = 1.0
	var au_distance: float = 0.0     # semi-major axis from Sol; unused for moons (0 for Sol itself)
	var parent: String = ""          # "" = orbits Sol directly; else the parent body's name
	var atmosphere: float = 0.0
	var atmo_falloff: float = 1.5
	var self_luminous: bool = false
	var emission_energy: float = 1.5
	var rings: float = 0.0
	var ring_tracks: int = 1
	var ring_tint: Color = Color(0.85, 0.75, 0.55)
	var ring_tilt_degrees: float = -1.0

	# Builds a ready-to-generate CanonicalBodyParams at the given display
	# radius — every caller lives at a different scale (Cosmic Forge's dev
	# viewer, Cockpit's close-up, System view's compressed map), so radius
	# is the one thing the caller must always supply itself.
	func to_params(display_radius: float) -> CanonicalBodyParams:
		var p := CanonicalBodyParams.new()
		p.body_name = body_name
		p.albedo_texture_path = "res://Assets/textures/%s/albedo.png" % texture_subdir
		p.fallback_color = fallback_color
		p.atmo_color = atmo_color
		p.radius = display_radius
		p.atmosphere = atmosphere
		p.atmo_falloff = atmo_falloff
		p.self_luminous = self_luminous
		p.emission_energy = emission_energy
		p.rings = rings
		p.ring_tracks = ring_tracks
		p.ring_tint = ring_tint
		p.ring_tilt_degrees = ring_tilt_degrees
		return p


static var _catalog: Dictionary = {}  # body_name -> Entry, built once on first access


static func get_entry(body_name: String) -> Entry:
	_ensure_built()
	return _catalog.get(body_name)


# All Sol-orbiting bodies (planets + Pluto), in real distance order —
# excludes moons. What System view's orbital map iterates over.
static func planets() -> Array[Entry]:
	_ensure_built()
	var result: Array[Entry] = []
	for entry: Entry in _catalog.values():
		if entry.parent == "" and entry.body_name != "Sol":
			result.append(entry)
	result.sort_custom(func(a: Entry, b: Entry) -> bool: return a.au_distance < b.au_distance)
	return result


static func sol() -> Entry:
	return get_entry("Sol")


static func _ensure_built() -> void:
	if not _catalog.is_empty():
		return

	var sol := Entry.new()
	sol.body_name = "Sol"
	sol.texture_subdir = "sol"
	sol.fallback_color = Color(1.0, 0.85, 0.55)
	sol.atmo_color = Color(1.0, 0.75, 0.35)
	sol.radius_ratio = 109.2
	sol.au_distance = 0.0
	sol.atmosphere = 0.5
	sol.atmo_falloff = 1.5
	sol.self_luminous = true
	sol.emission_energy = 1.5
	_catalog[sol.body_name] = sol

	var mercury := Entry.new()
	mercury.body_name = "Mercury"
	mercury.texture_subdir = "mercury"
	mercury.fallback_color = Color(0.55, 0.52, 0.48)
	mercury.atmo_color = Color(0.6, 0.6, 0.6)
	mercury.radius_ratio = 0.38
	mercury.au_distance = 0.39
	mercury.atmosphere = 0.0
	mercury.atmo_falloff = 1.5
	_catalog[mercury.body_name] = mercury

	var venus := Entry.new()
	venus.body_name = "Venus"
	venus.texture_subdir = "venus"
	venus.fallback_color = Color(0.80, 0.70, 0.45)
	venus.atmo_color = Color(0.95, 0.85, 0.55)
	venus.radius_ratio = 0.95
	venus.au_distance = 0.72
	venus.atmosphere = 0.9
	venus.atmo_falloff = 1.5
	_catalog[venus.body_name] = venus

	var earth := Entry.new()
	earth.body_name = "Earth"
	earth.texture_subdir = "earth"
	earth.fallback_color = Color(0.25, 0.35, 0.55)
	earth.atmo_color = Color(0.55, 0.75, 1.0)
	earth.radius_ratio = 1.0
	earth.au_distance = 1.00
	earth.atmosphere = 0.35
	earth.atmo_falloff = 1.5
	_catalog[earth.body_name] = earth

	# Mars' real atmosphere is ~0.6% the density of Earth's — default stays
	# low and dusty rather than reusing Earth's thick-haze default.
	var mars := Entry.new()
	mars.body_name = "Mars"
	mars.texture_subdir = "mars"
	mars.fallback_color = Color(0.60, 0.35, 0.25)
	mars.atmo_color = Color(0.85, 0.60, 0.45)
	mars.radius_ratio = 0.53
	mars.au_distance = 1.52
	mars.atmosphere = 0.08
	mars.atmo_falloff = 1.5
	_catalog[mars.body_name] = mars

	var luna := Entry.new()
	luna.body_name = "Luna"
	luna.texture_subdir = "moon"
	luna.fallback_color = Color(0.55, 0.55, 0.58)
	luna.atmo_color = Color(0.6, 0.6, 0.6)
	luna.radius_ratio = 0.27
	luna.parent = "Earth"
	luna.atmosphere = 0.0
	luna.atmo_falloff = 1.5
	_catalog[luna.body_name] = luna

	var jupiter := Entry.new()
	jupiter.body_name = "Jupiter"
	jupiter.texture_subdir = "jupiter"
	jupiter.fallback_color = Color(0.80, 0.65, 0.45)
	jupiter.atmo_color = Color(0.85, 0.75, 0.55)
	jupiter.radius_ratio = 10.97
	jupiter.au_distance = 5.20
	jupiter.atmosphere = 0.25
	jupiter.atmo_falloff = 1.2
	_catalog[jupiter.body_name] = jupiter

	# Fixed rings, not a slider-driven maybe — Saturn's rings (and its real
	# ~26.7° axial tilt) are a known fact.
	var saturn := Entry.new()
	saturn.body_name = "Saturn"
	saturn.texture_subdir = "saturn"
	saturn.fallback_color = Color(0.85, 0.72, 0.48)
	saturn.atmo_color = Color(0.90, 0.80, 0.55)
	saturn.radius_ratio = 9.14
	saturn.au_distance = 9.58
	saturn.atmosphere = 0.25
	saturn.atmo_falloff = 1.2
	saturn.rings = 0.7
	saturn.ring_tracks = 1
	saturn.ring_tint = Color(0.80, 0.72, 0.58)
	saturn.ring_tilt_degrees = 26.7
	_catalog[saturn.body_name] = saturn

	# Uranus is essentially tipped onto its side (real axial tilt ~97.8°),
	# which is exactly why its thin rings read as nearly vertical rather
	# than a flat disc like every other ringed body here.
	var uranus := Entry.new()
	uranus.body_name = "Uranus"
	uranus.texture_subdir = "uranus"
	uranus.fallback_color = Color(0.55, 0.80, 0.85)
	uranus.atmo_color = Color(0.60, 0.85, 0.90)
	uranus.radius_ratio = 3.98
	uranus.au_distance = 19.2
	uranus.atmosphere = 0.2
	uranus.atmo_falloff = 1.2
	uranus.rings = 0.03
	uranus.ring_tracks = 1
	uranus.ring_tint = Color(0.75, 0.80, 0.82)
	uranus.ring_tilt_degrees = 97.8
	_catalog[uranus.body_name] = uranus

	var neptune := Entry.new()
	neptune.body_name = "Neptune"
	neptune.texture_subdir = "neptune"
	neptune.fallback_color = Color(0.25, 0.35, 0.75)
	neptune.atmo_color = Color(0.35, 0.45, 0.90)
	neptune.radius_ratio = 3.86
	neptune.au_distance = 30.05
	neptune.atmosphere = 0.2
	neptune.atmo_falloff = 1.2
	_catalog[neptune.body_name] = neptune

	# Pluto's atmosphere is so thin it's negligible at this scale.
	var pluto := Entry.new()
	pluto.body_name = "Pluto"
	pluto.texture_subdir = "pluto"
	pluto.fallback_color = Color(0.75, 0.68, 0.60)
	pluto.atmo_color = Color(0.75, 0.70, 0.65)
	pluto.radius_ratio = 0.19
	pluto.au_distance = 39.5
	pluto.atmosphere = 0.0
	pluto.atmo_falloff = 1.5
	_catalog[pluto.body_name] = pluto
