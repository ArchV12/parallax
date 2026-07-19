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

# Scanner Array tier (0-4) required to detect this material at all — 0 means
# every player sees it from the very first survey, same as every material
# authored before this existed (Iron/Aluminum/Silicon/Titanium/Water Ice all
# default here). Deposits.deposits_for/deposit_for filter on this against
# Research.owned_tier("scanner_array") LIVE, at read time, not at survey
# time — upgrading Scanner Array immediately reveals more at an already-
# surveyed body, no re-survey needed (2026-07-18 design chat: tier gating
# is about what your CURRENT instrument can pick out of the body, same
# spirit as re-reading old data through a better filter).
@export var min_scanner_tier: int = 0
