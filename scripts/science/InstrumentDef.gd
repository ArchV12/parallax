class_name InstrumentDef
extends Resource

# One tier within an ActivityDef.instruments chain (Docs/Science and Knowledge
# System.md, "Activity Progression"). Instruments never expire or get
# replaced in place — an activity's chain just keeps advancing through them.

@export var id: String = ""
@export var display_name: String = ""

# Flavor/result lines a survey run with this instrument can produce, e.g.
# "Detect Common Ores" — see the vision doc's Resource Survey tier examples.
@export var capabilities: Array[String] = []
