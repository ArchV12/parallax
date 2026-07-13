class_name ResourceMaterialFinding
extends Resource

# One line of a Resource Survey's "DETECTED MATERIALS" report — qualitative,
# not numeric ("Common"/"Trace", not a percentage), per the sample the user
# gave. note_label/note_value is deliberately generic rather than a fixed
# "extraction" field: most materials pair Abundance with Extraction
# difficulty, but Water Ice pairs it with Location instead (see the sample)
# — this covers both without a separate field per material type.

@export var material_name: String = ""
@export var abundance: String = ""  # "Abundant" / "Common" / "Moderate" / "Trace" / "Confirmed" (presence-only, e.g. ice)
@export var note_label: String = ""  # "Extraction" or "Location"
@export var note_value: String = ""
