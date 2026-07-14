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
	var parent_distance_km: float = 0.0  # real semi-major axis around `parent`; only set for moons (0/unused otherwise) — see TravelCalc, Cockpit's moon anchoring
	var atmosphere: float = 0.0
	var atmo_falloff: float = 1.5
	var self_luminous: bool = false
	var emission_energy: float = 1.5
	var rings: float = 0.0
	var ring_tracks: int = 1
	var ring_tint: Color = Color(0.85, 0.75, 0.55)
	var ring_tilt_degrees: float = -1.0

	# --- Data-panel facts (2026-07-10) ---
	# Real astronomical values, for BodyInfoPanel.gd's readout — separate
	# from the rendering fields above, which are tuned for how a body LOOKS
	# rather than what it factually IS. Deliberately basic (no gameplay-
	# relevant properties like resources/biodiversity yet) — see the
	# planet-data-panel conversation in parallax-core-design-decisions memory.
	var body_type: String = ""      # "Terrestrial Planet", "Gas Giant", "Ice Giant", "Dwarf Planet", "Moon", "Star"
	var real_radius_km: float = 0.0
	# Orbital period in days — around Sol for a planet, around its parent for
	# a moon. 0 for Sol itself (doesn't orbit anything here).
	var orbital_period_days: float = 0.0
	var has_atmosphere: bool = false
	# Gas/ice giants (and Sol) have no solid surface at all, so "surface
	# pressure" isn't a meaningful number to show — distinct from a body that
	# genuinely has ~0 atm (Mercury, Luna), which IS meaningful.
	var has_solid_surface: bool = true
	var surface_pressure_atm: float = 0.0
	# Real moon counts run into the dozens for the gas/ice giants — not
	# practical to list or ever visit all of them. moon_count is already the
	# CURATED number to display (the full real total for most bodies, but a
	# capped "major moons only" figure for the giants); moon_count_is_capped
	# says which label the panel should use ("Moons" vs "Major Moons") so the
	# cap reads as a deliberate disclaimer, not an error. Only meaningful for
	# planets/dwarf planets (parent == "") — moons don't have their own moons.
	var moon_count: int = 0
	var moon_count_is_capped: bool = false
	# Star-only facts (body_type == "Star") — spectral classification and
	# photosphere temperature. Unused/blank for anything else.
	var spectral_type: String = ""
	var surface_temp_k: float = 0.0
	# true (default) = this entry has a real photographic texture and
	# to_params()/CanonicalBodyGenerator renders it, same as every planet.
	# false = PlanetarySystemView.gd instead builds this body procedurally
	# via MoonGenerator, seeded off body_name so it looks the same every
	# visit — used for every real moon here except Luna, which keeps its
	# specific canonical art (see the planetary-system-view conversation in
	# parallax-core-design-decisions memory). The facts above (radius,
	# orbital period, atmosphere, ...) are real either way — this flag is
	# purely about which renderer draws the body, not what's true about it.
	var use_canonical_art: bool = true

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


# Curated bodies first; falls through to a lazily-SYNTHESIZED Entry (not
# cached into _catalog — see _synthesize_asteroid_entry's own comment on
# why) for a registered asteroid, so Cockpit/TravelCalc/anything else that
# already assumes "get_entry returns non-null means this is a real body"
# just works for asteroids too, without them needing to know asteroids are
# a different kind of thing at all.
static func get_entry(body_name: String) -> Entry:
	_ensure_built()
	if _catalog.has(body_name):
		return _catalog[body_name]
	return _synthesize_asteroid_entry(body_name)


# Real au_distance/real_radius_km come from Research's registries
# (populated by SystemView the moment it actually spawns the asteroid —
# see Research.gd's own comments), NOT independently re-rolled here — the
# whole point is that every consumer of this Entry sees the EXACT same
# distance the player already saw placed on the System View map, not a
# second seeded guess that might not agree with it. Returns null (same as
# any other unrecognized id) if this asteroid hasn't actually been spawned/
# registered THIS session yet — an id merely shaped like a designation
# with no registered orbit isn't a real, travelable body.
#
# Deliberately NOT cached into _catalog: entries there get iterated wholesale
# by planets()/moons_of() (parent == "" would make an asteroid show up as a
# 9th "planet" in System view's own build loop, complete with a broken
# texture-less render and an orbit ring it shouldn't have) — asteroids must
# only ever be reachable by an exact get_entry(id) lookup, never enumerated.
static func _synthesize_asteroid_entry(body_name: String) -> Entry:
	if not AsteroidResourceGenerator.looks_like_asteroid_id(body_name):
		return null
	var au_distance := Research.asteroid_au_distance_for(body_name)
	if au_distance <= 0.0:
		return null
	var radius_km := Research.asteroid_radius_km_for(body_name)
	if radius_km <= 0.0:
		radius_km = 1.0  # defensive only — shouldn't happen once au_distance has resolved

	var e := Entry.new()
	e.body_name = body_name
	e.parent = ""  # orbits Sol directly, same as a planet — see Cockpit._asteroid_anchor_pos
	e.au_distance = au_distance
	e.body_type = "Asteroid"
	e.real_radius_km = radius_km
	e.radius_ratio = radius_km / 6371.0  # Earth-relative, same reference every other entry uses
	e.use_canonical_art = false
	return e


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


# All catalogued moons of the given planet, closest to farthest (by real
# orbital period around that planet, not around Sol) — what
# PlanetarySystemView.gd iterates over. Not every catalogued moon is
# necessarily this planet's FULL real moon count (see moon_count/
# moon_count_is_capped on Entry) — only the ones actually curated here.
static func moons_of(planet_name: String) -> Array[Entry]:
	_ensure_built()
	var result: Array[Entry] = []
	for entry: Entry in _catalog.values():
		if entry.parent == planet_name:
			result.append(entry)
	result.sort_custom(func(a: Entry, b: Entry) -> bool: return a.orbital_period_days < b.orbital_period_days)
	return result


# Compact constructor for a real moon whose ART is procedurally generated
# (MoonGenerator, seeded off its name) rather than a real texture — the
# facts themselves (radius, period, atmosphere) are still real. Most moons
# have no meaningful atmosphere; the two real exceptions (Titan, Triton)
# pass has_atmo/pressure explicitly.
static func _make_moon(moon_name: String, parent_name: String, radius_km: float, period_days: float,
		distance_km: float, has_atmo: bool = false, pressure_atm: float = 0.0) -> Entry:
	var m := Entry.new()
	m.body_name = moon_name
	m.parent = parent_name
	m.body_type = "Moon"
	m.real_radius_km = radius_km
	m.radius_ratio = radius_km / 6371.0  # Earth-relative, same reference every other entry uses
	m.orbital_period_days = period_days
	m.parent_distance_km = distance_km
	m.has_atmosphere = has_atmo
	m.has_solid_surface = true
	m.surface_pressure_atm = pressure_atm
	m.use_canonical_art = false
	return m


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
	sol.body_type = "Star"
	sol.real_radius_km = 695700.0
	sol.has_solid_surface = false
	sol.spectral_type = "G2V"
	sol.surface_temp_k = 5778.0
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
	mercury.body_type = "Terrestrial Planet"
	mercury.real_radius_km = 2439.7
	mercury.orbital_period_days = 88.0
	mercury.has_atmosphere = false
	mercury.surface_pressure_atm = 0.0
	mercury.moon_count = 0
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
	venus.body_type = "Terrestrial Planet"
	venus.real_radius_km = 6051.8
	venus.orbital_period_days = 224.7
	venus.has_atmosphere = true
	venus.surface_pressure_atm = 92.0
	venus.moon_count = 0
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
	earth.body_type = "Terrestrial Planet"
	earth.real_radius_km = 6371.0
	earth.orbital_period_days = 365.25
	earth.has_atmosphere = true
	earth.surface_pressure_atm = 1.0
	earth.moon_count = 1
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
	mars.body_type = "Terrestrial Planet"
	mars.real_radius_km = 3389.5
	mars.orbital_period_days = 687.0
	mars.has_atmosphere = true
	mars.surface_pressure_atm = 0.006
	mars.moon_count = 2
	_catalog[mars.body_name] = mars

	var luna := Entry.new()
	luna.body_name = "Luna"
	luna.texture_subdir = "moon"
	luna.fallback_color = Color(0.55, 0.55, 0.58)
	luna.atmo_color = Color(0.6, 0.6, 0.6)
	luna.radius_ratio = 0.27
	luna.parent = "Earth"
	luna.parent_distance_km = 384400.0
	luna.atmosphere = 0.0
	luna.atmo_falloff = 1.5
	luna.body_type = "Moon"
	luna.real_radius_km = 1737.4
	luna.orbital_period_days = 27.3  # around Earth, not Sol
	luna.has_atmosphere = false
	luna.surface_pressure_atm = 0.0
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
	jupiter.body_type = "Gas Giant"
	jupiter.real_radius_km = 69911.0
	jupiter.orbital_period_days = 4331.0
	jupiter.has_atmosphere = true
	jupiter.has_solid_surface = false
	jupiter.moon_count = 4  # the Galilean moons — real total is ~95
	jupiter.moon_count_is_capped = true
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
	saturn.body_type = "Gas Giant"
	saturn.real_radius_km = 58232.0
	saturn.orbital_period_days = 10747.0
	saturn.has_atmosphere = true
	saturn.has_solid_surface = false
	saturn.moon_count = 7  # the classical round moons — real total is ~146
	saturn.moon_count_is_capped = true
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
	uranus.body_type = "Ice Giant"
	uranus.real_radius_km = 25362.0
	uranus.orbital_period_days = 30589.0
	uranus.has_atmosphere = true
	uranus.has_solid_surface = false
	uranus.moon_count = 5  # the major moons — real total is 27
	uranus.moon_count_is_capped = true
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
	neptune.body_type = "Ice Giant"
	neptune.real_radius_km = 24622.0
	neptune.orbital_period_days = 59800.0
	neptune.has_atmosphere = true
	neptune.has_solid_surface = false
	neptune.moon_count = 1  # Triton, overwhelmingly dominant — real total is 14
	neptune.moon_count_is_capped = true
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
	pluto.body_type = "Dwarf Planet"
	pluto.real_radius_km = 1188.3
	pluto.orbital_period_days = 90560.0
	pluto.has_atmosphere = true  # trace, seasonal nitrogen atmosphere
	pluto.surface_pressure_atm = 0.00001
	pluto.moon_count = 5  # Charon + Styx, Nix, Kerberos, Hydra — the full known total
	_catalog[pluto.body_name] = pluto

	# --- Real moons, procedurally-generated art (2026-07-10) ---
	# Facts are real; the ART is generated (see Entry.use_canonical_art) —
	# see the planetary-system-view conversation in parallax-core-design-
	# decisions memory. Matches each planet's moon_count above exactly, in
	# real closest-to-farthest order (moons_of() sorts by orbital period).
	# Titan and Triton are the two real exceptions with a genuine atmosphere;
	# every other moon here has none worth showing.
	_catalog["Phobos"] = _make_moon("Phobos", "Mars", 11.1, 0.32, 9376.0)
	_catalog["Deimos"] = _make_moon("Deimos", "Mars", 6.2, 1.26, 23463.0)

	_catalog["Io"] = _make_moon("Io", "Jupiter", 1821.6, 1.77, 421700.0)
	_catalog["Europa"] = _make_moon("Europa", "Jupiter", 1560.8, 3.55, 671034.0)
	_catalog["Ganymede"] = _make_moon("Ganymede", "Jupiter", 2634.1, 7.15, 1070412.0)
	_catalog["Callisto"] = _make_moon("Callisto", "Jupiter", 2410.3, 16.69, 1882709.0)

	_catalog["Mimas"] = _make_moon("Mimas", "Saturn", 198.2, 0.94, 185539.0)
	_catalog["Enceladus"] = _make_moon("Enceladus", "Saturn", 252.1, 1.37, 237948.0)
	_catalog["Tethys"] = _make_moon("Tethys", "Saturn", 531.1, 1.89, 294619.0)
	_catalog["Dione"] = _make_moon("Dione", "Saturn", 561.4, 2.74, 377396.0)
	_catalog["Rhea"] = _make_moon("Rhea", "Saturn", 763.8, 4.52, 527108.0)
	# Titan's surface pressure is real — genuinely thicker than Earth's.
	_catalog["Titan"] = _make_moon("Titan", "Saturn", 2574.7, 15.95, 1221870.0, true, 1.45)
	_catalog["Iapetus"] = _make_moon("Iapetus", "Saturn", 734.5, 79.3, 3560820.0)

	_catalog["Miranda"] = _make_moon("Miranda", "Uranus", 235.8, 1.41, 129390.0)
	_catalog["Ariel"] = _make_moon("Ariel", "Uranus", 578.9, 2.52, 191020.0)
	_catalog["Umbriel"] = _make_moon("Umbriel", "Uranus", 584.7, 4.14, 266000.0)
	_catalog["Titania"] = _make_moon("Titania", "Uranus", 788.4, 8.71, 435910.0)
	_catalog["Oberon"] = _make_moon("Oberon", "Uranus", 761.4, 13.46, 583520.0)

	_catalog["Triton"] = _make_moon("Triton", "Neptune", 1353.4, 5.88, 354759.0, true, 0.00002)

	_catalog["Charon"] = _make_moon("Charon", "Pluto", 606.0, 6.39, 19591.0)
	_catalog["Styx"] = _make_moon("Styx", "Pluto", 5.0, 20.2, 42656.0)
	_catalog["Nix"] = _make_moon("Nix", "Pluto", 17.5, 24.9, 48694.0)
	_catalog["Kerberos"] = _make_moon("Kerberos", "Pluto", 6.0, 32.1, 57783.0)
	_catalog["Hydra"] = _make_moon("Hydra", "Pluto", 18.0, 38.5, 64738.0)
