class_name BuildingDef
extends Resource

# One tier of a passive Knowledge-generating structure (Docs/Buildings
# System.md). Applies `multiplier` against a body's NativeRate for
# `category_id` — a building on a body with native rate 0 for that category
# produces nothing regardless of tier.

@export var id: String = ""
@export var display_name: String = ""

# Matches a Research knowledge category id — reuses the EXISTING
# "geological"/"resource" ids where a Science Activity already owns that
# pool, rather than a separate parallel counter.
@export var category_id: String = ""

# 0-3, index within this category's tier array (Buildings.BUILDING_PATHS).
@export var tier: int = 0

@export var multiplier: float = 1.0

@export var credits_cost: int = 0

# Same freeform-string-keyed shape as TechnologyDef.materials_requirements.
@export var materials_requirements: Dictionary[String, int] = {}

# Same shape/semantics as TechnologyDef.knowledge_requirements — the
# Knowledge tier that must already be owned before this building tier can
# be constructed, on top of the credits/materials cost.
@export var knowledge_requirements: Dictionary[String, int] = {}

@export var description: String = ""
