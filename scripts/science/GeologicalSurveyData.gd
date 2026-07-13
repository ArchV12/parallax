class_name GeologicalSurveyData
extends Resource

# Hand-authored per-body Geological Survey report content — the rich,
# multi-field "flavor" report (Docs/Science and Knowledge System -
# Implementation Roadmap.md's Geological Survey discussion), as opposed to
# Resource Survey's flat one-line InstrumentDef.capabilities text. Deliberately
# its own narrow shape rather than a generic "SurveyReport" class — different
# Activities will want genuinely different fields (this is composition/
# features/activity-state/age/notes; a future Biological Survey report would
# want something else entirely), so forcing one shared schema now would be
# premature generalization for a system with exactly one example built.
#
# No per-field "minimum tier to reveal" gating yet — Geological Survey only
# has one known instrument tier (Geological Imager) so there's nothing to
# gate between. Revisit once a second tier actually exists.

@export var body_id: String = ""
@export var composition: Array[String] = []
@export var major_features: Array[String] = []
@export var volcanism: String = ""
@export var tectonics: String = ""
@export var erosion: String = ""
@export var estimated_age: String = ""
@export var notes: Array[String] = []
