class_name ActivityDef
extends Resource

# One of the ~12 permanent Science activities (Docs/Science and Knowledge
# System.md). Activities themselves never change — only which instruments
# entry the player currently owns advances as TechnologyDefs unlock (see the
# Research autoload, Phase 1).

@export var id: String = ""
@export var display_name: String = ""

# Matches the category key used in TechnologyDef.knowledge_requirements for
# any tech that grants an instrument in this activity's chain.
@export var knowledge_category: String = ""

# Ordered tier list. Index 0 is the free starting instrument — nothing
# unlocks it, the player just has it (see the "tools gate activities"
# decision in the roadmap doc).
@export var instruments: Array[InstrumentDef] = []

# --- Cockpit Activities Panel presentation (gateway/detail/active-operations
# flow) ---

@export var description: String = ""  # short one-line gateway blurb, e.g. "Identify available materials"
@export var icon: String = ""  # single glyph, e.g. "🔬" — placeholder until real icon assets exist

# In-fiction ("flavor") duration shown to the player — NOT how long the
# actual progress bar animation takes. Same compression principle travel
# already uses: the ship "really" takes this long, the player only waits a
# few real seconds. See ActivitiesPanel's animation duration (still
# BodyInfoPanel.SCAN_DURATION, unchanged) for the actual real-time wait.
@export var flavor_duration_seconds: int = 0

# Generic, per-Activity flavor text for the detail panel's "Potential
# Discoveries" list — deliberately NOT derived from real per-body data
# (would spoil the result before the survey even runs); same text every
# time regardless of location.
@export var potential_discoveries: Array[String] = []


static func format_duration(total_seconds: int) -> String:
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
