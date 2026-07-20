class_name NavScan
extends RefCounted

# Navigation Scanner reveal logic (2026-07-19 design brainstorm — see the
# Nav Scan / "unidentified blip" conversation). Replaces the old static
# KnownBodies.Entry.min_nav_tier gate (a body either met your owned tier or
# didn't render at all) with a dynamic radius check: a body reveals once
# you've scanned from somewhere within range of it, regardless of tier,
# given enough repositioning/patience — a low tier just means a smaller
# radius per scan, not a hard content ceiling.
#
# Position simplification: this checks RADIAL distance from the star
# (Entry.au_distance) rather than true 3D position. The codebase has no
# shared, continuous, cross-scene ephemeris to check real 3D position
# against — SystemView.gd's own orbital angles are rerolled randomly every
# time that scene loads and only animate forward while it stays open;
# Cockpit.gd's "universe" placement is a fixed seeded direction with no
# orbital motion at all. Radial distance from the star is the one position
# fact that's real, static, and identical no matter which scene fired the
# scan — "how far out in the system are you, and how far out is the
# candidate" is a legible navigational-range reading even though it drops
# the "something drifted into range while you stood still" nuance the
# original brainstorm floated. Repositioning yourself and rescanning is
# still the intended core loop; only the passive-drift edge case is out of
# scope here.
#
# resolve() takes an explicit candidate list rather than hardcoding
# KnownBodies.planets_of() so a moon/asteroid population can reuse it
# without a rewrite — see run() (planets+asteroids, AU-scale, star-relative)
# vs. run_for_moons() (moons, KM-scale, PLANET-relative) below: two
# genuinely different distance spaces, not one generalized further, since
# Entry.au_distance is meaningless for a moon (see its own "unused for
# moons" comment) and Entry.parent_distance_km is meaningless for a planet.

# AU radius revealed per Navigation Scanner tier (0-4, see
# Docs/Ship Equipment.md: Basic / Short Range / Extended Range / Deep
# Stellar / Stellar Cartography). Anchored loosely against Proxima's own
# real figures — Proxima b sits at 0.0485 AU (just inside Tier 0's reach,
# matching its real-world status as an easy, confirmed detection) while c
# sits at 1.5 AU (needs Tier 2+). Tier 4's radius is simply larger than any
# system in the game rather than a special "reveal all" branch. Exact
# numbers are tunable via playtesting, not load-bearing on their own.
const RADIUS_AU_BY_TIER: Array[float] = [0.08, 0.6, 2.5, 12.0, 9999.0]

# Scan duration in seconds per tier — faster scanners commit you for less
# time. T0/T4 anchors given directly by design; T1-T3 interpolated.
const DURATION_SEC_BY_TIER: Array[float] = [5.0, 3.0, 1.5, 0.8, 0.5]

# Tier-scaled KM radius for scanning MOONS specifically, within a single
# planetary system (see run_for_moons below) — a wholly separate scale
# from RADIUS_AU_BY_TIER above, not a unit conversion of it. Moon-to-planet
# distances (thousands to low millions of km — real examples: Miranda
# 129,390 km from Uranus, Callisto 1,882,709 km from Jupiter) are a
# completely different order of magnitude than star-to-planet AU distances;
# converting RADIUS_AU_BY_TIER into km would make even Tier 0 (0.08 AU ≈
# 12,000,000 km) already cover every moon in any curated system from
# anywhere in it, making the radius gate meaningless there. Same equipment,
# same owned tier index (_owned_tier is shared) — just a naturally smaller
# absolute range when hunting for nearby moons instead of planets across a
# whole star system. Anchored against Proxima c's own two invented moons
# (118,000 km and 305,000 km out) so Tier 0 catches the near one but not
# the far one, matching the same "T0 = short range, T4 = everything" shape
# the AU table already has.
const RADIUS_KM_BY_TIER: Array[float] = [150000.0, 400000.0, 1000000.0, 3000000.0, 999999999.0]


static func _owned_tier() -> int:
	return clampi(Research.owned_tier("navigation_scanner"), 0, RADIUS_AU_BY_TIER.size() - 1)


static func owned_radius_au() -> float:
	return RADIUS_AU_BY_TIER[_owned_tier()]


static func owned_radius_km() -> float:
	return RADIUS_KM_BY_TIER[_owned_tier()]


static func scan_duration_sec() -> float:
	return DURATION_SEC_BY_TIER[_owned_tier()]


# The player's own current radial distance from the star they're at (0.0 if
# standing at the star itself) — the "where am I scanning from" the whole
# mechanic keys off. Falls back to the PARENT planet's au_distance when
# standing on a moon (Entry.au_distance is "unused for moons" per its own
# doc comment, so reading it directly would silently treat a player at
# Proxima c I as if they were back at the star) — same "moon → parent"
# resolution ViewSwitcher._current_planet_for_view already uses elsewhere.
# Real KnownBodies fact, not scene-simulation state, so it's identical
# whether read from Cockpit or SystemView.
static func player_origin_au() -> float:
	var entry := KnownBodies.get_entry(PlayerState.location_id)
	if entry == null:
		return 0.0
	if entry.parent != "":
		var parent_entry := KnownBodies.get_entry(entry.parent)
		return parent_entry.au_distance if parent_entry != null else 0.0
	return entry.au_distance


static func player_star_system() -> String:
	var entry := KnownBodies.get_entry(PlayerState.location_id)
	return entry.star_system if entry != null else "Sol"


# Runs one scan from the player's current real position against every
# planet AND every currently-registered asteroid of the player's current
# star system (2026-07-19 — Proxima Centauri's own debris field is the
# first non-Sol asteroid content; asteroids only ever join the candidate
# list via Research.asteroid_ids_for_star_system, since they're not
# pre-enumerated anywhere the way planets are). Already-revealed bodies are
# skipped (never re-rolled, never un-revealed). Returns the names newly
# revealed by THIS call, so a caller (SystemView) can react to/animate
# exactly what changed rather than diffing the whole system.
static func run() -> Array[String]:
	var star := player_star_system()
	var candidates := KnownBodies.planets_of(star)
	for id: String in Research.asteroid_ids_for_star_system(star):
		var entry := KnownBodies.get_entry(id)
		if entry != null:
			candidates.append(entry)
	return resolve(candidates, player_origin_au())


static func resolve(candidates: Array[KnownBodies.Entry], origin_au: float) -> Array[String]:
	var radius := owned_radius_au()
	var newly_revealed: Array[String] = []
	for entry: KnownBodies.Entry in candidates:
		if Discoveries.is_scanned(entry.body_name):
			continue
		if absf(entry.au_distance - origin_au) <= radius:
			Discoveries.mark_scanned(entry.body_name)
			newly_revealed.append(entry.body_name)
	return newly_revealed


# Runs one scan from the player's current position WITHIN the planetary
# system they're currently viewing (PlanetarySystemView, not SystemView),
# against every moon of planet_name — the moon equivalent of run() above,
# genuinely separate rather than sharing resolve() because a moon's real
# position is measured from its PARENT PLANET (Entry.parent_distance_km),
# not a star (Entry.au_distance is meaningless for a moon). Origin is 0.0
# if the player is at the planet itself, or that moon's own
# parent_distance_km if they're currently docked at one of its OTHER
# moons — same "scan from the star reveals nearby planets, scan from a
# planet reveals nearby moons" shape run()/resolve() already establish, one
# level down.
static func run_for_moons(planet_name: String) -> Array[String]:
	var origin_km := 0.0
	if PlayerState.location_id != planet_name:
		var loc_entry := KnownBodies.get_entry(PlayerState.location_id)
		if loc_entry != null and loc_entry.parent == planet_name:
			origin_km = loc_entry.parent_distance_km

	var radius := owned_radius_km()
	var newly_revealed: Array[String] = []
	for entry: KnownBodies.Entry in KnownBodies.moons_of(planet_name):
		if Discoveries.is_scanned(entry.body_name):
			continue
		if absf(entry.parent_distance_km - origin_km) <= radius:
			Discoveries.mark_scanned(entry.body_name)
			newly_revealed.append(entry.body_name)
	return newly_revealed
