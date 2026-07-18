class_name ActiveOperation
extends RefCounted

# Session-only runtime state for one in-progress Activity (survey or mining)
# tracked by the Operations autoload — deliberately RefCounted, not Resource,
# same "no save system yet, in-memory now" pattern used everywhere else (see
# Docs/Science and Knowledge System - Implementation Roadmap.md's flagged
# dependency). Never hand-authored, always constructed by Operations.start_*.

enum Status { RUNNING, COMPLETE }

var op_id: String = ""
var activity_id: String = ""

# The operation's OWN target body — deliberately captured here, not re-read
# from PlayerState.location_id at resolution/display time, since the player
# can travel elsewhere while this is still running (the whole point of this
# system). Whatever body this points at is where the reward/report belongs,
# regardless of where the player physically is when it resolves.
var location_id: String = ""

# --- Survey-kind fields (resource_survey/geological_survey) — a single
# fixed-duration resolve, unused by mining (see below). ---
var duration: float = 0.0
var elapsed: float = 0.0
var status: Status = Status.RUNNING

# The in-fiction ("flavor") countdown shown to the player — see
# ActivityDef.flavor_duration_seconds' own comment on the compression
# principle.
var flavor_duration_seconds: int = 0

# Populated once, at resolution (Operations._resolve) — never recomputed
# later. "See Results" reads this back rather than re-running whatever
# produced it, so viewing results twice can never double-award.
var result: Dictionary = {}

# --- Mining-kind fields — continuous, no fixed duration/elapsed/result at
# all (Operations._tick_mining ticks this every frame while RUNNING; there
# is no COMPLETE state, it just runs until stopped/departed/depleted — see
# Operations.stop_mining/_finish_mining). Empty/0 for survey-kind
# operations. ---
var deposit_material: String = ""
var mining_yield_accumulator: float = 0.0  # fractional progress toward the next whole committed unit
var mining_session_yield: int = 0          # whole units actually committed to Deposits this session — what the UI displays


func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)
