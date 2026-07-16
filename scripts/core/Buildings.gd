extends Node

# Session-scoped registry of constructed passive structures (Docs/Buildings
# System.md). Deliberately NOT part of Operations.gd — ship operations
# (Survey/Mining) are attention-limited (the ship can only do one thing at a
# time), so Operations owns a per-kind concurrency model and stops Mining on
# PlayerState.travel_started. Buildings are the opposite: left behind, run
# forever, many tick simultaneously across many locations regardless of
# where the ship currently is. This autoload owns its own _process and never
# touches PlayerState.travel_started — that absence is deliberate, not an
# oversight.
#
# In-memory only, resets on New Game, same as every other system here (no
# save system exists anywhere yet).

# Fires only on an actual tier change (construction/upgrade) — a rare event,
# safe to trigger a full UI rebuild from. Do NOT wire UI rebuilds to
# Research.knowledge_changed instead — that fires on every whole-point tick
# across every structure in the game.
signal structure_constructed(category_id: String, body_id: String)

# Divides native_rate * multiplier into a per-second Knowledge rate. Tuned
# (2026-07-15, after the original 1500.0 placeholder read as "nothing is
# happening" in actual play — a Beacon at 0.008/sec never visibly ticked) so
# a Beacon-tier structure (multiplier 0.25) on a typical body (native rate
# ~48-55) lands around 0.2-0.23/sec — a whole Knowledge point roughly every
# 5 seconds, a satisfying passive trickle rather than an invisible one. Top
# tier (multiplier 1.5, 6x a Beacon) scales up to 1-2/sec on a good body.
const RATE_TIME_CONSTANT := 60.0

const ENGINEERING_BONUS_PER_CONSTRUCTION := 10

# category_id -> ordered tier array of BuildingDef .tres paths. Hand-authored
# and hardcoded, same spirit as Research.ACTIVITY_PATHS — only "geological"
# has real data this phase; the other 5 categories are roadmapped.
const BUILDING_PATHS := {
	"geological": [
		"res://Data/Buildings/Geology/building_geological_survey_beacon.tres",
		"res://Data/Buildings/Geology/building_geological_outpost.tres",
		"res://Data/Buildings/Geology/building_geological_research_facility.tres",
		"res://Data/Buildings/Geology/building_planetary_geoscience_complex.tres",
	],
}

# category_id -> the Science Activity id that must have surveyed a body at
# least once before construction is allowed there — mirrors Mining's own
# existing prerequisite (Research.has_resource_survey, see ActivitiesPanel's
# _is_available_now). Extensible: future categories just add an entry here.
const SURVEY_PREREQUISITE_BY_CATEGORY := {
	"geological": "geological_survey",
}


class Structure extends RefCounted:
	var category_id: String
	var body_id: String
	var tier: int = 0
	var knowledge_accumulator: float = 0.0
	var total_contributed: float = 0.0  # display-only running total, mirrors ActiveOperation.mining_session_yield


var _building_defs: Dictionary = {}  # category_id -> Array[BuildingDef], loaded once
var _structures: Dictionary = {}     # "category_id:body_id" -> Structure


func _init() -> void:
	for id: String in BUILDING_PATHS:
		var list: Array[BuildingDef] = []
		for path: String in BUILDING_PATHS[id]:
			list.append(load(path))
		_building_defs[id] = list


func reset_for_new_game() -> void:
	_structures.clear()


# Only categories with real .tres data — the UI iterates this so the
# roadmapped 5 categories correctly show no CONSTRUCTION row anywhere yet.
func category_ids() -> Array:
	return _building_defs.keys()


func _key(category_id: String, body_id: String) -> String:
	return "%s:%s" % [category_id, body_id]


func tier_at(category_id: String, body_id: String) -> int:
	var s: Structure = _structures.get(_key(category_id, body_id))
	return s.tier if s != null else -1


func current_building_def(category_id: String, body_id: String) -> BuildingDef:
	var tier := tier_at(category_id, body_id)
	var defs: Array = _building_defs.get(category_id, [])
	return defs[tier] if tier >= 0 and tier < defs.size() else null


# The next tier constructable at body_id, or null if already at max tier (or
# this category has no tiers authored yet).
func next_building_def(category_id: String, body_id: String) -> BuildingDef:
	var defs: Array = _building_defs.get(category_id, [])
	var next_index := tier_at(category_id, body_id) + 1
	return defs[next_index] if next_index < defs.size() else null


func has_required_survey(category_id: String, body_id: String) -> bool:
	var activity_id: String = SURVEY_PREREQUISITE_BY_CATEGORY.get(category_id, "")
	return activity_id != "" and Research.tier_surveyed_at(activity_id, body_id) >= 0


func can_construct(category_id: String, body_id: String) -> bool:
	var def := next_building_def(category_id, body_id)
	if def == null or not has_required_survey(category_id, body_id):
		return false
	for cat: String in def.knowledge_requirements:
		if Research.knowledge(cat) < def.knowledge_requirements[cat]:
			return false
	if Economy.balance < def.credits_cost:
		return false
	for material_name: String in def.materials_requirements:
		if Deposits.material_amount(material_name) < def.materials_requirements[material_name]:
			return false
	return true


# Atomic: can_construct() already verified every gate, so the two spends
# below should never individually fail — kept as defensive early-outs, same
# trust model Research.craft_technology() uses around Deposits.spend_materials.
func construct(category_id: String, body_id: String) -> bool:
	if not can_construct(category_id, body_id):
		return false
	var def := next_building_def(category_id, body_id)
	if not Economy.spend_credits(def.credits_cost):
		return false
	if not Deposits.spend_materials(def.materials_requirements):
		return false
	var key := _key(category_id, body_id)
	var s: Structure = _structures.get(key)
	if s == null:
		s = Structure.new()
		s.category_id = category_id
		s.body_id = body_id
		_structures[key] = s
	s.tier = def.tier
	Research.add_knowledge("engineering", ENGINEERING_BONUS_PER_CONSTRUCTION)
	structure_constructed.emit(category_id, body_id)
	return true


func total_contributed(category_id: String, body_id: String) -> float:
	var s: Structure = _structures.get(_key(category_id, body_id))
	return s.total_contributed if s != null else 0.0


func structures_at(body_id: String) -> Array[Structure]:
	var result: Array[Structure] = []
	for s: Structure in _structures.values():
		if s.body_id == body_id:
			result.append(s)
	return result


func knowledge_per_second(category_id: String, body_id: String) -> float:
	var def := current_building_def(category_id, body_id)
	if def == null:
		return 0.0
	return NativeRate.for_category(category_id, body_id) * def.multiplier / RATE_TIME_CONSTANT


# Same fractional-accumulator-committed-on-whole-unit-crossing idiom
# Operations._tick_mining already uses — applied per-structure instead of
# per-operation, and running unconditionally regardless of ship location.
func _process(delta: float) -> void:
	for s: Structure in _structures.values():
		var def := current_building_def(s.category_id, s.body_id)
		if def == null:
			continue
		var rate := NativeRate.for_category(s.category_id, s.body_id)
		if rate <= 0.0:
			continue
		s.knowledge_accumulator += rate * def.multiplier * delta / RATE_TIME_CONSTANT
		var whole := int(s.knowledge_accumulator)
		if whole > 0:
			s.knowledge_accumulator -= whole
			s.total_contributed += whole
			Research.add_knowledge(s.category_id, whole)
