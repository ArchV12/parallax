class_name TechnologyDef
extends Resource

# A Scientific Milestone (Docs/Science and Knowledge System.md). Checked
# whenever Knowledge changes (Phase 3) against knowledge_requirements; once
# every category threshold is met, grants_instrument becomes the new current
# instrument for whichever ActivityDef owns it.

@export var id: String = ""
@export var display_name: String = ""

# Knowledge category id -> threshold, e.g. {"resource": 120}. More than one
# key makes this a multi-discipline requirement (see the Prototype Plasma
# Drive example — Atmospheric/Physics/Radiation all required at once).
@export var knowledge_requirements: Dictionary[String, int] = {}

@export_multiline var unlock_text: String = ""

@export var grants_instrument: InstrumentDef
