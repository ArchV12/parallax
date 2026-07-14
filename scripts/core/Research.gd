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

# Every known Activity's data file. Hand-authored and hardcoded here rather
# than scanned from disk — activities are a small, fixed, designed set (see
# Question 2 Answer.md), same spirit as TravelCalc.ENGINE_TIERS.
const ACTIVITY_PATHS := {
	"resource_survey": "res://Data/Science/ResourceSurvey/activity_resource_survey.tres",
	"geological_survey": "res://Data/Science/GeologicalSurvey/activity_geological_survey.tres",
	"mining": "res://Data/Science/Mining/activity_mining.tres",
}

# Activities the player owns a starting (tier 0) instrument for from the very
# beginning — "tools gate activities, not the reverse" (roadmap doc). Mining
# is owned from the start too, but gated per-location instead by
# has_resource_survey (see below) — ActivitiesPanel is what actually hides
# its AVAILABLE row until a Resource Survey has resolved at the current body.
const STARTING_ACTIVITIES := ["resource_survey", "geological_survey", "mining"]

# Each activity's TechnologyDef chain, in tier order — index N is the tech
# that advances owned_tier from N to N+1 (there's no entry for tier 0, the
# free starting instrument nothing unlocks). Hand-authored/hardcoded for the
# same reason ACTIVITY_PATHS is. geological_survey has no entry yet — only
# its starting tier (Geological Imager) is known so far, nothing to unlock
# it TO yet; next_technology() already returns null gracefully for that.
const TECHNOLOGY_PATHS := {
	"resource_survey": [
		"res://Data/Science/ResourceSurvey/tech_advanced_spectrometer.tres",
		"res://Data/Science/ResourceSurvey/tech_deep_penetration_scanner.tres",
		"res://Data/Science/ResourceSurvey/tech_quantum_mineral_imager.tres",
		"res://Data/Science/ResourceSurvey/tech_exotic_matter_resonator.tres",
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


# Loads eagerly in _init (object construction), not _ready — _ready is
# deferred a frame relative to when other autoloads' _ready bodies run in at
# least some execution contexts, and nothing should be able to observe this
# singleton before its activity data exists.
func _init() -> void:
	for id: String in ACTIVITY_PATHS:
		_activities[id] = load(ACTIVITY_PATHS[id])
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


# True when surveying body_id with this activity right now would actually
# teach something new — never surveyed before, OR the player's CURRENT
# instrument tier is strictly better than whatever tier was used last time
# here. This is the gate ActivitiesPanel uses to decide between a normal
# tappable (re-)survey row and a passive "Show Results" row for a body
# already fully covered at the player's present equipment level.
func can_survey_for_new_info(activity_id: String, body_id: String) -> bool:
	return owned_tier(activity_id) > tier_surveyed_at(activity_id, body_id)


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
func known_activities() -> Array[String]:
	var result: Array[String] = []
	for id: String in _activities:
		result.append(id)
	return result


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
# tier of a body's data only when first needed" rule). Still null for
# anything else (a real moon with no authored survey, a typo, ...) — same
# honesty as before this existed.
func resource_data_for(body_id: String) -> ResourceSurveyData:
	if not _resource_data.has(body_id):
		_ensure_asteroid_data(body_id)
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
# is currently affordable (Deposits.material_amount).
func can_craft(activity_id: String) -> bool:
	var tech := next_technology(activity_id)
	if tech == null or not _requirements_met(tech):
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
	if not Deposits.spend_materials(tech.materials_requirements):
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
