class_name ResourceSurveyData
extends Resource

# Hand-authored per-body Resource Survey report content — the qualitative
# "DETECTED MATERIALS" list (see ResourceMaterialFinding), Resource Survey's
# counterpart to GeologicalSurveyData. Its own narrow shape for the same
# reason that class documents: different Activities want genuinely
# different report fields, not one forced-generic schema.

@export var body_id: String = ""
@export var materials: Array[ResourceMaterialFinding] = []
