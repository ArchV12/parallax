extends Node

# Session-scoped Science & Knowledge state — which instrument tier the player
# currently owns per Activity, and accumulated Knowledge per category. Same
# in-memory-only shape as Discoveries.gd/PlayerState.gd (no save system yet —
# see the roadmap doc's flagged dependency); reset_for_new_game() follows the
# same pattern, called from MainMenu._on_new_game alongside the others.
#
# Docs/Science and Knowledge System - Implementation Roadmap.md, Phase 1.

# Fired once per TechnologyDef granted by _check_milestones — the single
# source of truth for "a milestone happened," regardless of what caused the
# Knowledge change (a survey, the F2 Cheat Menu, or anything future). Any
# other signal built on top of a specific trigger (e.g. an earlier version
# had ActivitiesPanel emit its own copy only from its RUN SURVEY handler)
# silently misses every OTHER path that calls add_knowledge.
signal milestone_reached(tech: TechnologyDef)

# Fired on EVERY add_knowledge() call, unlike milestone_reached (tier-unlock
# only) — a live-ticking readout (the Buildings top bar, which commits small
# fractional-accumulated amounts every frame per structure) needs every
# change, not just milestone crossings.
signal knowledge_changed(category_id: String, new_total: int)

# Fired the first time a materials-gated TechnologyDef's Knowledge
# requirements become met, but BEFORE it's actually crafted/granted —
# distinct from milestone_reached, which only fires once the tier is
# actually owned. Fires exactly once per tech (_notified_blueprints below),
# not on every subsequent add_knowledge/craft-check call. EarthTransmission-
# Banner (Cockpit.gd) is wired to THIS signal, not milestone_reached, per an
# explicit user ask (2026-07-18) — the transmission should read as "Earth
# sent us the blueprint," not "the equipment is built." Deliberately does
# NOT also drive a named HUD toast (a first pass tried "New Sub-Light Engine
# upgrade available: Fusion Drive," per Docs/Upgrading.md's own example) —
# removed per user follow-up: naming the tech before the player even opens
# the transmission spoiled the reveal. The unnamed "Incoming Earth
# Transmission" button (EarthTransmissionBanner) is the only surfacing of
# this signal now; the name stays hidden until actually opened.
#
# NOTE: a materials-FREE tech never emits this — it auto-grants straight
# through milestone_reached the instant Knowledge is met (see
# _check_milestones below), never passing through the materials-gate branch
# this signal fires from. Every TechnologyDef today has a real materials
# cost, so this is a latent gap, not a live bug — but a future materials-
# free tech would silently get no Earth Transmission at all under the
# current wiring.
signal blueprint_unlocked(slot_id: String, tech: TechnologyDef)

# Every known Activity's data file. Hand-authored and hardcoded here rather
# than scanned from disk — activities are a small, fixed, designed set (see
# Question 2 Answer.md), same spirit as TravelCalc.ENGINE_TIERS.
#
# 2026-07-18: also holds the 6 Ship Equipment slots (Docs/Ship Equipment.md,
# Docs/Upgrading.md) — EQUIPMENT_SLOT_PATHS below. They share this exact dict
# (and _activities/_owned_tier/_technologies) rather than a parallel system:
# the underlying mechanics (owned tier, next tech, can_craft, craft) are
# already fully generic over an id string, and the one place that iterates
# ALL ids (known_activities(), read by ResearchPanel) is being rewritten to
# use equipment_slot_ids() for equipment and stay separate — see that
# function's own comment. Science Activity ids stay hardcoded lists
# elsewhere (is_survey_kind, ANOMALY_SOURCE_ACTIVITIES) that equipment slot
# ids are simply never added to, so nothing survey-specific gets confused by
# the new ids sharing a dictionary.
const ACTIVITY_PATHS := {
	"resource_survey": "res://Data/Science/ResourceSurvey/activity_resource_survey.tres",
	"geological_survey": "res://Data/Science/GeologicalSurvey/activity_geological_survey.tres",
	"astrophysics_survey": "res://Data/Science/AstrophysicsSurvey/activity_astrophysics_survey.tres",
	"life_sciences_survey": "res://Data/Science/LifeSciencesSurvey/activity_life_sciences_survey.tres",
	"atmospheric_survey": "res://Data/Science/AtmosphericSurvey/activity_atmospheric_survey.tres",
	"mining": "res://Data/Science/Mining/activity_mining.tres",
}

# The 6 Ship Equipment slots (Docs/Ship Equipment.md), in that doc's own
# display order — this exact order is what ResearchPanel's 6 rows use (see
# equipment_slot_ids()). scanner_array supersedes resource_survey's OWN
# instrument chain (see that ActivityDef's now-trimmed single-tier
# instruments array, and TECHNOLOGY_PATHS below no longer having a
# resource_survey entry) — Scanner Array is a ship-wide slot, not a synonym
# for the Resource Survey activity, so its chain lives under its own id even
# though it reuses/renames that same original tier data.
const EQUIPMENT_SLOT_PATHS := {
	"sub_light_engines": "res://Data/ShipEquipment/SubLightEngines/activity_sub_light_engines.tres",
	"beyond_light_engines": "res://Data/ShipEquipment/BeyondLightEngines/activity_beyond_light_engines.tres",
	"scanner_array": "res://Data/ShipEquipment/ScannerArray/activity_scanner_array.tres",
	"mining_system": "res://Data/ShipEquipment/MiningSystem/activity_mining_system.tres",
	"cargo_hold": "res://Data/ShipEquipment/CargoHold/activity_cargo_hold.tres",
	"navigation_scanner": "res://Data/ShipEquipment/NavigationScanner/activity_navigation_scanner.tres",
}

# Activities the player owns a starting (tier 0) instrument for from the very
# beginning — "tools gate activities, not the reverse" (roadmap doc). Mining
# is owned from the start too, but gated per-location instead by
# has_resource_survey (see below) — ActivitiesPanel is what actually hides
# its AVAILABLE row until a Resource Survey has resolved at the current body.
#
# Every Equipment slot is owned from tier 0 too (Docs/Ship Equipment.md's
# Starting Loadout). Beyond Light Engines' own tier 0 is a real "None"
# InstrumentDef (Data/ShipEquipment/BeyondLightEngines/instrument_none.tres)
# rather than owned_tier starting at -1/LOCKED like an un-owned Activity —
# deliberately, so it uses the exact same "index == owned_tier" tier/tech
# indexing every other slot already relies on (next_technology/can_craft/
# craft_technology/_check_milestones all assume owned_tier starts at 0 with
# a real, if empty, instrument there). Its own instruments array therefore
# has 6 entries (None + 5 real drives) against 5 TECHNOLOGY_PATHS entries,
# unlike every other slot's 5-instruments-vs-4-techs shape.
const STARTING_ACTIVITIES := [
	"resource_survey", "geological_survey", "astrophysics_survey", "life_sciences_survey", "atmospheric_survey", "mining",
	"sub_light_engines", "beyond_light_engines", "scanner_array", "mining_system", "cargo_hold", "navigation_scanner",
]

# Each activity's TechnologyDef chain, in tier order — index N is the tech
# that advances owned_tier from N to N+1 (there's no entry for tier 0, the
# free starting instrument nothing unlocks). Hand-authored/hardcoded for the
# same reason ACTIVITY_PATHS is. geological_survey has no entry yet — only
# its starting tier (Geological Imager) is known so far, nothing to unlock
# it TO yet; next_technology() already returns null gracefully for that.
# resource_survey deliberately has NO entry anymore — its 4-tier chain moved
# to scanner_array below verbatim (same tech_*.tres files, just re-keyed) the
# moment Scanner Array became the real ship-wide slot; leaving both active
# would have meant two parallel, disconnected progressions unlocking the
# same instruments under two different ids.
#
# beyond_light_engines has 5 entries, not 4, unlike every other chain here —
# it has no free tier 0, so its FIRST tier (Warp Bubble Generator) needs its
# own real unlock tech too, not just tiers 1-4.
const TECHNOLOGY_PATHS := {
	"scanner_array": [
		"res://Data/Science/ResourceSurvey/tech_advanced_spectrometer.tres",
		"res://Data/Science/ResourceSurvey/tech_deep_penetration_scanner.tres",
		"res://Data/Science/ResourceSurvey/tech_quantum_mineral_imager.tres",
		"res://Data/Science/ResourceSurvey/tech_exotic_matter_resonator.tres",
	],
	"sub_light_engines": [
		"res://Data/ShipEquipment/SubLightEngines/tech_fusion_drive.tres",
		"res://Data/ShipEquipment/SubLightEngines/tech_improved_fusion.tres",
		"res://Data/ShipEquipment/SubLightEngines/tech_antimatter_drive.tres",
		"res://Data/ShipEquipment/SubLightEngines/tech_relativistic_cap.tres",
	],
	"beyond_light_engines": [
		"res://Data/ShipEquipment/BeyondLightEngines/tech_warp_bubble_generator.tres",
		"res://Data/ShipEquipment/BeyondLightEngines/tech_alcubierre_drive.tres",
		"res://Data/ShipEquipment/BeyondLightEngines/tech_folded_space_drive.tres",
		"res://Data/ShipEquipment/BeyondLightEngines/tech_wormhole_threader.tres",
		"res://Data/ShipEquipment/BeyondLightEngines/tech_singularity_drive.tres",
	],
	"mining_system": [
		"res://Data/ShipEquipment/MiningSystem/tech_precision_mining_laser.tres",
		"res://Data/ShipEquipment/MiningSystem/tech_plasma_cutting_array.tres",
		"res://Data/ShipEquipment/MiningSystem/tech_molecular_disassembler.tres",
		"res://Data/ShipEquipment/MiningSystem/tech_graviton_extraction_rig.tres",
	],
	"cargo_hold": [
		"res://Data/ShipEquipment/CargoHold/tech_reinforced_hold.tres",
		"res://Data/ShipEquipment/CargoHold/tech_modular_cargo_bay.tres",
		"res://Data/ShipEquipment/CargoHold/tech_compression_hold.tres",
		"res://Data/ShipEquipment/CargoHold/tech_quantum_vault.tres",
	],
	"navigation_scanner": [
		"res://Data/ShipEquipment/NavigationScanner/tech_short_range_detector.tres",
		"res://Data/ShipEquipment/NavigationScanner/tech_extended_range_array.tres",
		"res://Data/ShipEquipment/NavigationScanner/tech_deep_stellar_scan.tres",
		"res://Data/ShipEquipment/NavigationScanner/tech_stellar_cartography_suite.tres",
	],
}

# Hand-authored per-body Geological Survey report content (GeologicalSurveyData)
# — body_id -> path. Only bodies with actual authored content appear here;
# geological_data_for() returns null for anything else, same "not every body
# has content yet" honesty as TECHNOLOGY_PATHS above.
const GEOLOGICAL_DATA_PATHS := {
	"Luna": "res://Data/Science/GeologicalSurvey/luna_geological_data.tres",
	"Earth": "res://Data/Science/GeologicalSurvey/earth_geological_data.tres",
	"Mars": "res://Data/Science/GeologicalSurvey/mars_geological_data.tres",
}

# Hand-authored per-body Resource Survey report content (ResourceSurveyData)
# — body_id -> path. Same "only bodies with actual content appear here"
# honesty as GEOLOGICAL_DATA_PATHS. Real Sol bodies' known facts constrain
# Geological Survey content, but elemental abundance isn't public knowledge
# the same way "Mars is a red desert" is — so unlike Geological Survey, this
# doesn't need to track real surveyed data, just stay roughly plausible.
const RESOURCE_DATA_PATHS := {
	"Earth": "res://Data/Science/ResourceSurvey/earth_resource_data.tres",
	"Mars": "res://Data/Science/ResourceSurvey/mars_resource_data.tres",
	"Luna": "res://Data/Science/ResourceSurvey/luna_resource_data.tres",
	# 2026-07-18 — Scanner Array tier-gating pass (see ResourceMaterialFinding.
	# min_scanner_tier): moons/gas giants/ice giant/dwarf planet/star all
	# newly authored, none had Resource Survey data before this.
	"Io": "res://Data/Science/ResourceSurvey/io_resource_data.tres",
	"Europa": "res://Data/Science/ResourceSurvey/europa_resource_data.tres",
	"Titan": "res://Data/Science/ResourceSurvey/titan_resource_data.tres",
	"Triton": "res://Data/Science/ResourceSurvey/triton_resource_data.tres",
	"Jupiter": "res://Data/Science/ResourceSurvey/jupiter_resource_data.tres",
	"Saturn": "res://Data/Science/ResourceSurvey/saturn_resource_data.tres",
	"Uranus": "res://Data/Science/ResourceSurvey/uranus_resource_data.tres",
	"Neptune": "res://Data/Science/ResourceSurvey/neptune_resource_data.tres",
	"Pluto": "res://Data/Science/ResourceSurvey/pluto_resource_data.tres",
	"Sol": "res://Data/Science/ResourceSurvey/sol_resource_data.tres",
	# Completes every PLANET's coverage — Mercury/Venus were the only two
	# curated planets still missing survey data.
	"Mercury": "res://Data/Science/ResourceSurvey/mercury_resource_data.tres",
	"Venus": "res://Data/Science/ResourceSurvey/venus_resource_data.tres",
}

var _activities: Dictionary = {}  # activity_id -> ActivityDef, loaded once at startup
var _technologies: Dictionary = {}  # activity_id -> Array[TechnologyDef], loaded once at startup, tier order
var _geological_data: Dictionary = {}  # body_id -> GeologicalSurveyData, loaded once at startup
# body_id -> ResourceSurveyData — the curated 3 (Earth/Mars/Luna) loaded
# once at startup below; any asteroid designation gets added lazily the
# first time resource_data_for() sees it (see that function) and stays
# cached here for the rest of the session, same "generate once, persist"
# shape as the curated entries, just generated instead of authored.
var _resource_data: Dictionary = {}
# body_id -> real radius in km, ONLY for the lazily-generated asteroid
# entries above (curated bodies already have this on their KnownBodies.
# Entry) — KnownBodies.get_entry synthesizes a real Entry for an asteroid
# id from this (and _asteroid_au_distance below), which is what actually
# lets Cockpit/TravelCalc treat a registered asteroid like any other body.
var _asteroid_radius_km: Dictionary = {}
# body_id -> real AU distance from Sol, registered by SystemView the
# instant it actually spawns an asteroid (see SystemView._spawn_dummy_
# asteroid/_spawn_trojan) — NOT independently rolled here the way radius_km
# above is. AU distance depends on which population (Main Belt/NEA/
# Centaur/Trojan) an asteroid belongs to, which only SystemView's spawn
# logic actually knows; re-deriving it from just the id elsewhere would risk
# landing on a DIFFERENT number than what the player actually saw on the
# map — the exact "oh that's close by!" inconsistency this registry exists
# to prevent. An asteroid with no entry here has simply never been spawned/
# seen yet, and is correctly treated as not a real, travelable body still.
var _asteroid_au_distance: Dictionary = {}

# activity_id -> owned instrument tier index. -1 means the activity hasn't
# been unlocked at all yet (no instrument owned); 0 is the first, free tier.
var _owned_tier: Dictionary = {}

# knowledge_category id -> accumulated Knowledge. Never spent, only ever grows
# (Docs/Science and Knowledge System.md, "Knowledge").
var _knowledge: Dictionary = {}

# "activity_id:body_id" -> the highest instrument tier a survey has ever
# resolved there with. Two jobs: (1) Mining's "must survey here first"
# prerequisite (Docs/Mining.md) — has_resource_survey below, resource_survey
# specifically — and (2) the Knowledge-award gate in run_survey — re-running
# the SAME survey at a body you've already covered with your CURRENT tier
# awards nothing (there's nothing new to learn re-scanning with the same
# equipment), but a genuinely better tier than whatever was used last time
# re-opens it, since better equipment really would find something new. Flat
# "surveyed or not" was the original shape here and let a player rack up
# infinite Knowledge just re-running the same survey forever — this is the
# fix for that, general across both survey activities, not resource_survey-
# only the way the old boolean was.
var _surveyed_tier: Dictionary = {}

# TechnologyDef (object identity, Resources compare by reference) -> true,
# once blueprint_unlocked has fired for it — guards against re-emitting on
# every subsequent add_knowledge()/_check_milestones() call while the
# player just hasn't crafted it yet.
var _notified_blueprints: Dictionary = {}

# CheatMenu's "FREE UPGRADES" toggle (2026-07-18) — bypasses both the
# Knowledge and materials checks in can_craft/craft_technology below, so a
# tester can walk the full Ship Equipment tier ladder without grinding real
# Knowledge or materials. Deliberately NOT cleared by reset_for_new_game,
# unlike PlayerState.engine_tier_override — a tester driving repeated New
# Games to retest the upgrade pipeline shouldn't have to re-toggle it each
# time; it's a session-level dev switch, not gameplay state.
var free_upgrades: bool = false


# Loads eagerly in _init (object construction), not _ready — _ready is
# deferred a frame relative to when other autoloads' _ready bodies run in at
# least some execution contexts, and nothing should be able to observe this
# singleton before its activity data exists.
func _init() -> void:
	for id: String in ACTIVITY_PATHS:
		_activities[id] = load(ACTIVITY_PATHS[id])
	for id: String in EQUIPMENT_SLOT_PATHS:
		_activities[id] = load(EQUIPMENT_SLOT_PATHS[id])
	for id: String in TECHNOLOGY_PATHS:
		var list: Array[TechnologyDef] = []
		for path: String in TECHNOLOGY_PATHS[id]:
			list.append(load(path))
		_technologies[id] = list
	for id: String in GEOLOGICAL_DATA_PATHS:
		_geological_data[id] = load(GEOLOGICAL_DATA_PATHS[id])
	for id: String in RESOURCE_DATA_PATHS:
		_resource_data[id] = load(RESOURCE_DATA_PATHS[id])
	reset_for_new_game()


func reset_for_new_game() -> void:
	_owned_tier.clear()
	_knowledge.clear()
	_surveyed_tier.clear()
	_notified_blueprints.clear()
	for id: String in _activities:
		_owned_tier[id] = 0 if id in STARTING_ACTIVITIES else -1


func _survey_key(activity_id: String, body_id: String) -> String:
	return "%s:%s" % [activity_id, body_id]


# The highest instrument tier this activity has ever surveyed body_id with,
# or -1 if never.
func tier_surveyed_at(activity_id: String, body_id: String) -> int:
	return _surveyed_tier.get(_survey_key(activity_id, body_id), -1)


# True once resource_survey has EVER resolved here, regardless of tier —
# Mining's prerequisite only cares that deposits have been identified at
# all, not which instrument found them.
func has_resource_survey(body_id: String) -> bool:
	return tier_surveyed_at("resource_survey", body_id) >= 0


# category_id -> the survey Activity id that can reveal an anomaly in that
# category — see NativeRate.anomaly_for/ANOMALY_TYPES. No dedicated
# "anomalies_survey" activity exists; any of these 4 can independently roll
# one at a body.
const ANOMALY_SOURCE_ACTIVITIES := {
	"resource": "resource_survey",
	"geological": "geological_survey",
	"astrophysics": "astrophysics_survey",
	"life_sciences": "life_sciences_survey",
}

# True once the player has actually SURVEYED a body with at least one
# activity whose category independently rolled a real anomaly there — not
# just "an anomaly mathematically exists" (NativeRate.anomaly_for is a pure
# function, always the same ground truth regardless of discovery), but "the
# player has actually found one." Gates Anomalies-category construction (see
# Buildings.has_required_survey's anomalies special-case).
func has_detected_anomaly(body_id: String) -> bool:
	for category_id: String in ANOMALY_SOURCE_ACTIVITIES:
		var activity_id: String = ANOMALY_SOURCE_ACTIVITIES[category_id]
		if tier_surveyed_at(activity_id, body_id) >= 0 and NativeRate.anomaly_for(body_id, category_id) != null:
			return true
	return false


# True when surveying body_id with this activity right now would actually
# teach something new — never surveyed before, OR the player's CURRENT
# instrument tier is strictly better than whatever tier was used last time
# here. This is the gate ActivitiesPanel uses to decide between a normal
# tappable (re-)survey row and a passive "Show Results" row for a body
# already fully covered at the player's present equipment level.
func can_survey_for_new_info(activity_id: String, body_id: String) -> bool:
	return owned_tier(activity_id) > tier_surveyed_at(activity_id, body_id)


# Resource/Geological/Astrophysics/Life Sciences/Atmospheric Survey — the
# activities that award Knowledge via run_survey and can go stale at a body
# (see can_survey_for_new_info above). Mining is the one activity_id that
# isn't a Survey (continuous, never resolves through run_survey at all).
# Single source of truth for both Operations.gd (which activities the
# Arrival Scan System auto-fires — see start_all_surveys) and any UI that
# still needs to distinguish Survey-kind rows from Mining's own.
func is_survey_kind(activity_id: String) -> bool:
	return activity_id == "resource_survey" or activity_id == "geological_survey" or activity_id == "astrophysics_survey" \
			or activity_id == "life_sciences_survey" or activity_id == "atmospheric_survey"


func activity_def(activity_id: String) -> ActivityDef:
	return _activities.get(activity_id)


func is_unlocked(activity_id: String) -> bool:
	return owned_tier(activity_id) >= 0


func owned_tier(activity_id: String) -> int:
	return _owned_tier.get(activity_id, -1)


# The InstrumentDef the player currently has for this activity, or null if the
# activity isn't unlocked yet.
func current_instrument(activity_id: String) -> InstrumentDef:
	var tier := owned_tier(activity_id)
	if tier < 0:
		return null
	var def := activity_def(activity_id)
	if def == null or tier >= def.instruments.size():
		return null
	return def.instruments[tier]


# Every activity id the player currently has at least a starting instrument
# for — what a Cockpit "what can I do here" panel would list (Phase 2).
func available_activities() -> Array[String]:
	var result: Array[String] = []
	for id: String in _activities:
		if is_unlocked(id):
			result.append(id)
	return result


# Every activity id that has data at all, unlocked or not — what the
# Research dashboard lists (Phase 4), unlike available_activities above
# (which is unlock-filtered, for Cockpit's action list).
#
# 2026-07-18: no longer used by ResearchPanel (see equipment_slot_ids()
# below) — Science Activities don't have their own Research-panel display
# anymore now that instrument progression lives entirely on Ship Equipment
# slots. Left in place; still a generically useful "every id with data"
# query, and nothing currently needs it, but it's cheap to keep working.
func known_activities() -> Array[String]:
	var result: Array[String] = []
	for id: String in _activities:
		result.append(id)
	return result


# The 6 Ship Equipment slot ids, in Docs/Ship Equipment.md's own display
# order — what ResearchPanel's 6 rows iterate. Deliberately a fixed ordered
# array, not EQUIPMENT_SLOT_PATHS.keys() (Dictionary key order isn't a
# stable, designed ordering the way this array's literal order is).
const EQUIPMENT_SLOT_IDS: Array[String] = [
	"sub_light_engines", "beyond_light_engines", "scanner_array", "mining_system", "cargo_hold", "navigation_scanner",
]


func equipment_slot_ids() -> Array[String]:
	return EQUIPMENT_SLOT_IDS


# Debug/cheat tooling (2026-07-19, HUD's F3) — instantly grants the TOP tier
# of every Ship Equipment slot at once, bypassing craft_technology's
# Knowledge/Materials gate entirely (same spirit as free_upgrades below, a
# one-shot "max everything" instead of "let the player craft freely from
# here"). Top tier is read directly off each slot's own real instrument
# chain length (instruments.size() - 1) rather than a hardcoded "4" — safe
# for Beyond Light Engines' own 6-entry chain (None + 5 real drives) without
# any special-casing. grant_tier's own "no-ops backward" floor makes this
# safe to call repeatedly or after some tiers are already owned.
func max_all_equipment() -> void:
	for slot_id: String in equipment_slot_ids():
		var activity: ActivityDef = _activities.get(slot_id)
		if activity == null:
			continue
		grant_tier(slot_id, activity.instruments.size() - 1)


# The TechnologyDef that would advance this activity from its currently
# owned tier to the next, or null if it's not unlocked yet or already at the
# top of its known chain ("Future Developments: Unknown," Phase 4).
func next_technology(activity_id: String) -> TechnologyDef:
	var tier := owned_tier(activity_id)
	if tier < 0:
		return null
	var techs: Array = _technologies.get(activity_id, [])
	if tier >= techs.size():
		return null
	return techs[tier]


# Grants ownership of a specific instrument tier for an activity — used by
# the milestone system (Phase 3) once a TechnologyDef's requirements are met,
# and by debug/cheat tooling in the meantime. No-ops backward (a tier can
# only ever advance, never regress).
func grant_tier(activity_id: String, tier: int) -> void:
	if tier > owned_tier(activity_id):
		_owned_tier[activity_id] = tier


func knowledge(category_id: String) -> int:
	return _knowledge.get(category_id, 0)


# Hand-authored rich Geological Survey report for this body if one exists
# (see GEOLOGICAL_DATA_PATHS); for an asteroid designation that hasn't been
# rolled yet, generates and caches one instead — same "generate the first
# time it's actually asked for, then persist for the rest of the session"
# shape resource_data_for/_ensure_asteroid_data already use, just for the
# Geological rather than Resource report (see AsteroidGeologicalGenerator).
# Still null for anything else (a real moon with no authored survey, a
# typo, ...) — same honesty as before this existed.
func geological_data_for(body_id: String) -> GeologicalSurveyData:
	if not _geological_data.has(body_id) and AsteroidResourceGenerator.looks_like_asteroid_id(body_id):
		_geological_data[body_id] = AsteroidGeologicalGenerator.generate(body_id)
	return _geological_data.get(body_id)


# Hand-authored rich Resource Survey report for this body if one exists
# (see RESOURCE_DATA_PATHS); for an asteroid designation (see
# AsteroidResourceGenerator.looks_like_asteroid_id) that hasn't been rolled
# yet, generates and caches one instead — there's no way to hand-author a
# file for an id that doesn't exist until a seeded population rolls it at
# runtime (see the universe-generation-architecture memory's "generate each
# tier of a body's data only when first needed" rule). 2026-07-18: the same
# "generate what doesn't need bespoke authorship" idea now also covers
# every catalogued moon WITHOUT a hand-authored file (see
# _ensure_moon_data/MoonResourceGenerator) — Luna/Io/Europa/Titan/Triton
# keep their real files, everything else (Phobos, Ganymede, Enceladus,
# Charon, ...) rolls procedurally the first time it's asked for. Still null
# for anything genuinely unrecognized (a typo, an id KnownBodies has never
# heard of) — same honesty as before this existed. 2026-07-19: the same
# "generate what doesn't need bespoke authorship" idea now also covers any
# Star/Terrestrial Planet/Dwarf Planet/Gas Giant/Ice Giant OUTSIDE Sol (see
# _ensure_planet_data/PlanetResourceGenerator) — every Sol planet/Sol itself
# is still hand-authored, this only ever fires for a body like Proxima
# Centauri or its planets, which had NO procedural fallback at all until now
# and silently returned null.
func resource_data_for(body_id: String) -> ResourceSurveyData:
	if not _resource_data.has(body_id):
		_ensure_asteroid_data(body_id)
		_ensure_moon_data(body_id)
		_ensure_planet_data(body_id)
	return _resource_data.get(body_id)


# Real radius (km) for a procedurally-generated asteroid, or 0.0 if
# body_id isn't one. Independent of whether a Resource Survey has ever
# actually run there — KnownBodies.get_entry needs this for DISPLAY
# purposes (Cockpit's arrival size) the moment an asteroid is first seen,
# not only once a player has surveyed it — so this rolls/caches the same
# data resource_data_for does, just via the shared _ensure_asteroid_data
# rather than depending on that function having been called first.
func asteroid_radius_km_for(body_id: String) -> float:
	if not _asteroid_radius_km.has(body_id):
		_ensure_asteroid_data(body_id)
	return _asteroid_radius_km.get(body_id, 0.0)


# Shared by resource_data_for/asteroid_radius_km_for — rolls+caches BOTH
# pieces of an asteroid's procedural data together in one pass (same seed,
# same generate() call — see AsteroidResourceGenerator), regardless of
# which one was asked for first. No-ops for anything already cached or
# that doesn't look like an asteroid id at all.
func _ensure_asteroid_data(body_id: String) -> void:
	if _resource_data.has(body_id) or not AsteroidResourceGenerator.looks_like_asteroid_id(body_id):
		return
	var rolled := AsteroidResourceGenerator.generate(body_id)
	_resource_data[body_id] = rolled["survey"]
	_asteroid_radius_km[body_id] = rolled["radius_km"]


# Companion to _ensure_asteroid_data above, same no-op-if-already-cached
# shape — but for catalogued Moon-type bodies instead of procedural
# asteroid designations. No radius to roll/cache here (unlike asteroids, a
# moon's real_radius_km is already a curated KnownBodies fact), so this
# only ever needs to fill in _resource_data. KnownBodies.get_entry already
# covers real moons AND asteroids alike, so the body_type == "Moon" check
# is what keeps this from double-generating for an asteroid id that
# _ensure_asteroid_data above already claimed.
func _ensure_moon_data(body_id: String) -> void:
	if _resource_data.has(body_id):
		return
	var entry := KnownBodies.get_entry(body_id)
	if entry == null or entry.body_type != "Moon":
		return
	_resource_data[body_id] = MoonResourceGenerator.generate(body_id)


# Companion to _ensure_asteroid_data/_ensure_moon_data above, same
# no-op-if-already-cached shape — covers everything else a real KnownBodies
# entry can be (Star, Terrestrial Planet, Dwarf Planet, Gas Giant, Ice
# Giant; see PlanetResourceGenerator.COVERED_BODY_TYPES) that isn't already
# hand-authored, a Moon, or an asteroid. Every Sol body of these types
# already has a RESOURCE_DATA_PATHS entry (so _resource_data.has(body_id)
# is already true by the time this runs for any of them) — this only ever
# actually fires for a non-Sol body like Proxima Centauri or its planets.
func _ensure_planet_data(body_id: String) -> void:
	if _resource_data.has(body_id):
		return
	var entry := KnownBodies.get_entry(body_id)
	if entry == null or not PlanetResourceGenerator.COVERED_BODY_TYPES.has(entry.body_type):
		return
	_resource_data[body_id] = PlanetResourceGenerator.generate(body_id)


# Registered by SystemView the instant it actually spawns an asteroid — see
# _asteroid_au_distance's own comment on why this is a registry, not
# something re-derived from the id like radius_km is.
func register_asteroid_orbit(body_id: String, au_distance: float) -> void:
	_asteroid_au_distance[body_id] = au_distance


# Real AU distance from Sol for a REGISTERED asteroid (see
# register_asteroid_orbit), or 0.0 if this id has never actually been
# spawned/seen yet — KnownBodies.get_entry treats 0.0 as "not a real body,"
# same as null everywhere else in this game.
func asteroid_au_distance_for(body_id: String) -> float:
	return _asteroid_au_distance.get(body_id, 0.0)


# Adds Knowledge and checks every activity's next TechnologyDef against the
# new totals, granting (and returning) any that are now satisfied — Phase 3's
# milestone checker, run on every Knowledge change rather than only from
# run_survey, so any future caller of add_knowledge gets it for free.
func add_knowledge(category_id: String, amount: int) -> Array[TechnologyDef]:
	_knowledge[category_id] = knowledge(category_id) + amount
	knowledge_changed.emit(category_id, _knowledge[category_id])
	return _check_milestones()


# Walks every activity's tech chain from its currently owned tier, granting
# (in order) any TechnologyDef whose knowledge_requirements are now fully
# met — a `while`, not a single `if`, so a large-enough Knowledge jump can
# clear more than one tier in one call rather than needing a second
# add_knowledge to notice the next one. A tech with a real materials_
# requirements cost stops the walk instead of auto-granting (see
# craft_technology below for the explicit path that actually grants it) —
# can't skip past an un-crafted prototype to check the tier after it, so
# this also means further tiers in THAT chain wait until the materials-
# gated one is crafted, even if their own Knowledge is already satisfied.
func _check_milestones() -> Array[TechnologyDef]:
	var granted: Array[TechnologyDef] = []
	for activity_id: String in _technologies:
		var techs: Array = _technologies[activity_id]
		var tier := owned_tier(activity_id)
		while tier >= 0 and tier < techs.size():
			var tech: TechnologyDef = techs[tier]
			if not _requirements_met(tech):
				break
			if not tech.materials_requirements.is_empty():
				if not _notified_blueprints.has(tech):
					_notified_blueprints[tech] = true
					blueprint_unlocked.emit(activity_id, tech)
				break
			grant_tier(activity_id, tier + 1)
			granted.append(tech)
			milestone_reached.emit(tech)
			tier += 1
	return granted


func _requirements_met(tech: TechnologyDef) -> bool:
	for category_id: String in tech.knowledge_requirements:
		if knowledge(category_id) < tech.knowledge_requirements[category_id]:
			return false
	return true


# Knowledge-only check on the activity's next tier — true the instant
# _check_milestones would have auto-granted it, HAD it no materials cost.
# Distinct from can_craft below (which also requires materials to be
# affordable) so a Craft screen can show "requirements met, but you can't
# afford it yet" instead of just a flat locked/unlocked state.
func is_craftable(activity_id: String) -> bool:
	var tech := next_technology(activity_id)
	return tech != null and _requirements_met(tech)


# Whether craft_technology(activity_id) would actually succeed right now —
# Knowledge requirements met AND every material in materials_requirements
# is currently affordable (Deposits.material_amount). free_upgrades (see
# that var's comment) skips both checks — only whether a next tier exists
# at all still gates it.
func can_craft(activity_id: String) -> bool:
	var tech := next_technology(activity_id)
	if tech == null:
		return false
	if free_upgrades:
		return true
	if not _requirements_met(tech):
		return false
	for material_name: String in tech.materials_requirements:
		if Deposits.material_amount(material_name) < tech.materials_requirements[material_name]:
			return false
	return true


# The explicit, player-triggered counterpart to _check_milestones' auto-
# grant — spends the next tier's materials_requirements (Deposits.
# spend_materials — atomic, no-ops entirely if anything's unaffordable) and
# grants it: same grant_tier + milestone_reached.emit _check_milestones
# already does for a materials-free tech, just behind a manual call instead
# of firing the instant Knowledge alone is satisfied. Re-checks can_craft
# itself (defensive — a caller may have last checked it some UI frames ago,
# e.g. a button press after the panel rendered). Re-runs _check_milestones
# afterward (not add_knowledge — no Knowledge changed) so that if the NEXT
# tier in the chain is materials-free and its own Knowledge is already
# satisfied, it cascades and auto-grants immediately rather than waiting on
# some unrelated future Knowledge change to notice it. Returns null if
# can_craft was false.
func craft_technology(activity_id: String) -> TechnologyDef:
	if not can_craft(activity_id):
		return null
	var tech := next_technology(activity_id)
	if not free_upgrades and not Deposits.spend_materials(tech.materials_requirements):
		return null  # can_craft already checked this — defensive only
	var tier := owned_tier(activity_id)
	grant_tier(activity_id, tier + 1)
	milestone_reached.emit(tech)
	_check_milestones()
	return tech


# Flat award per survey run, regardless of instrument tier or activity —
# a placeholder (roadmap Phase 2 scope note), same spirit as Phase 0's
# placeholder TechnologyDef thresholds. Real balancing is a later pass.
const SURVEY_KNOWLEDGE_AWARD := 10

# Runs a survey at the player's current instrument level for this activity —
# awards Knowledge in the activity's category and returns what happened, for
# the UI to display (including any newly granted TechnologyDefs, under
# "milestones"). Empty Dictionary (no-op) if the activity isn't unlocked.
#
# Knowledge is only actually awarded if can_survey_for_new_info was true
# going in (re-checked here, defensively — ActivitiesPanel's UI is what
# normally prevents starting a survey at all once a body's fully covered at
# the current tier, replacing the row with "Show Results" instead of BEGIN
# SURVEY, but this stays the real source of truth regardless of what UI
# path reached it). Either way, records the CURRENT tier as the highest
# that's surveyed this body — including a 0-Knowledge re-run, so repeatedly
# re-running at the same tier can never re-trigger the award.
func run_survey(activity_id: String, location_id: String) -> Dictionary:
	var instrument := current_instrument(activity_id)
	var def := activity_def(activity_id)
	if instrument == null or def == null:
		return {}
	var current_tier := owned_tier(activity_id)
	var awarded := SURVEY_KNOWLEDGE_AWARD if can_survey_for_new_info(activity_id, location_id) else 0
	var granted: Array[TechnologyDef] = []
	if awarded > 0:
		granted = add_knowledge(def.knowledge_category, awarded)
	var key := _survey_key(activity_id, location_id)
	_surveyed_tier[key] = maxi(current_tier, _surveyed_tier.get(key, -1))
	return {
		"instrument": instrument,
		"knowledge_category": def.knowledge_category,
		"knowledge_awarded": awarded,
		"milestones": granted,
	}
