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
var _resource_data: Dictionary = {}  # body_id -> ResourceSurveyData, loaded once at startup

# activity_id -> owned instrument tier index. -1 means the activity hasn't
# been unlocked at all yet (no instrument owned); 0 is the first, free tier.
var _owned_tier: Dictionary = {}

# knowledge_category id -> accumulated Knowledge. Never spent, only ever grows
# (Docs/Science and Knowledge System.md, "Knowledge").
var _knowledge: Dictionary = {}

# body_id -> true, once a Resource Survey has resolved there. A genuinely new
# gate — distinct from _owned_tier's instrument-ownership check, which is
# global, not per-location — needed for Mining's "must survey here first"
# prerequisite (Docs/Mining.md).
var _surveyed_locations: Dictionary = {}


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
	_surveyed_locations.clear()
	for id: String in _activities:
		_owned_tier[id] = 0 if id in STARTING_ACTIVITIES else -1


func mark_surveyed(body_id: String) -> void:
	_surveyed_locations[body_id] = true


func has_resource_survey(body_id: String) -> bool:
	return _surveyed_locations.get(body_id, false)


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


# Hand-authored rich Geological Survey report for this body, or null if none
# has been written yet (see GEOLOGICAL_DATA_PATHS).
func geological_data_for(body_id: String) -> GeologicalSurveyData:
	return _geological_data.get(body_id)


# Hand-authored rich Resource Survey report for this body, or null if none
# has been written yet (see RESOURCE_DATA_PATHS).
func resource_data_for(body_id: String) -> ResourceSurveyData:
	return _resource_data.get(body_id)


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
# add_knowledge to notice the next one.
func _check_milestones() -> Array[TechnologyDef]:
	var granted: Array[TechnologyDef] = []
	for activity_id: String in _technologies:
		var techs: Array = _technologies[activity_id]
		var tier := owned_tier(activity_id)
		while tier >= 0 and tier < techs.size():
			var tech: TechnologyDef = techs[tier]
			if not _requirements_met(tech):
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


# Flat award per survey run, regardless of instrument tier or activity —
# a placeholder (roadmap Phase 2 scope note), same spirit as Phase 0's
# placeholder TechnologyDef thresholds. Real balancing is a later pass.
const SURVEY_KNOWLEDGE_AWARD := 10

# Runs a survey at the player's current instrument level for this activity —
# awards Knowledge in the activity's category and returns what happened, for
# the UI to display (including any newly granted TechnologyDefs, under
# "milestones"). Empty Dictionary (no-op) if the activity isn't unlocked.
# location_id marks that body surveyed (see has_resource_survey) when this
# was specifically a Resource Survey — Mining's prerequisite gate.
func run_survey(activity_id: String, location_id: String) -> Dictionary:
	var instrument := current_instrument(activity_id)
	var def := activity_def(activity_id)
	if instrument == null or def == null:
		return {}
	var granted := add_knowledge(def.knowledge_category, SURVEY_KNOWLEDGE_AWARD)
	if activity_id == "resource_survey":
		mark_surveyed(location_id)
	return {
		"instrument": instrument,
		"knowledge_category": def.knowledge_category,
		"knowledge_awarded": SURVEY_KNOWLEDGE_AWARD,
		"milestones": granted,
	}
