extends Node

# Session-scoped registry of in-progress Activities (surveys, and from Phase
# 5, mining) — the same relationship PlayerState already has to travel
# (is_traveling/travel_elapsed ticking in _process/travel_completed signal):
# because this is an autoload, it survives change_scene_to_file, which is
# the whole point — ActivitiesPanel used to run each operation's timing as a
# Tween/coroutine living on itself, silently abandoned the instant Cockpit's
# scene tree was freed (GO-ing anywhere, or even just switching to System
# View). This is the fix: Operations owns ticking AND resolution; UI
# (ActivitiesPanel, Phase 2) becomes a pure poller/renderer over it, the
# same relationship ConsolePanel already has to PlayerState.travel_progress().
#
# _operations is a Dictionary (op_id -> ActiveOperation), not a single
# scalar "the one running thing" — a deliberate collection from day one so
# a future multiple-concurrent-operations feature (the user's own example:
# probes/ships working elsewhere) is an extension, not a rewrite. Only ONE
# operation may be RUNNING at a time for now (see can_start/has_running_
# operation) — that rule lives here, not baked into the data shape.

signal operation_started(op_id: String)
# Fired AFTER resolution has already run (op.result is populated) — see
# _resolve. Consumers never need to call anything to "finish" an operation;
# it's already fully resolved by the time they hear about it.
signal operation_completed(op_id: String)
signal operation_dismissed(op_id: String)

var _operations: Dictionary = {}  # op_id -> ActiveOperation
var _next_op_id: int = 0


# Only checks for a RUNNING operation, not "any operation at all" —
# COMPLETE-but-undismissed operations must NOT block starting a new one
# (results are meant to be viewed whenever the player gets around to it,
# per the passive "COMPLETED — See Results / X" design; blocking new work
# on an unacknowledged old result would contradict that). This means
# multiple DIFFERENT activities can legitimately sit COMPLETE-undismissed
# at once even under the "one running at a time" rule — each gets its own
# row in ActivitiesPanel regardless (see operation_for_activity).
func can_start() -> bool:
	return not has_running_operation()


func has_running_operation() -> bool:
	for op: ActiveOperation in _operations.values():
		if op.status == ActiveOperation.Status.RUNNING:
			return true
	return false


func running_operation() -> ActiveOperation:
	for op: ActiveOperation in _operations.values():
		if op.status == ActiveOperation.Status.RUNNING:
			return op
	return null


# Just one of possibly several COMPLETE-undismissed operations (see
# can_start's comment) — a convenience for callers that don't care WHICH
# one, not what ActivitiesPanel's own per-activity row building uses (that
# goes through operation_for_activity instead).
func completed_operation() -> ActiveOperation:
	for op: ActiveOperation in _operations.values():
		if op.status == ActiveOperation.Status.COMPLETE:
			return op
	return null


func operation_for_activity(activity_id: String) -> ActiveOperation:
	for op: ActiveOperation in _operations.values():
		if op.activity_id == activity_id:
			return op
	return null


func get_operation(op_id: String) -> ActiveOperation:
	return _operations.get(op_id)


func progress(op_id: String) -> float:
	var op := get_operation(op_id)
	return op.progress() if op != null else 0.0


func remaining(op_id: String) -> float:
	var op := get_operation(op_id)
	return op.remaining() if op != null else 0.0


# location_id is the operation's own target — see ActiveOperation's comment
# on why this is captured now rather than re-read from PlayerState later.
func start_survey(activity_id: String, location_id: String) -> String:
	var op := ActiveOperation.new()
	_next_op_id += 1
	op.op_id = str(_next_op_id)
	op.activity_id = activity_id
	op.location_id = location_id
	op.duration = BodyInfoPanel.SCAN_DURATION
	_operations[op.op_id] = op
	operation_started.emit(op.op_id)
	return op.op_id


# Removes a COMPLETE operation without ever having shown its results —
# no-ops silently for a RUNNING op (nothing should be able to dismiss work
# still in progress; cancellation, if ever added, is a different action).
func dismiss(op_id: String) -> void:
	var op := get_operation(op_id)
	if op == null or op.status != ActiveOperation.Status.COMPLETE:
		return
	_operations.erase(op_id)
	operation_dismissed.emit(op_id)


func reset_for_new_game() -> void:
	_operations.clear()


func _process(delta: float) -> void:
	for op: ActiveOperation in _operations.values():
		if op.status != ActiveOperation.Status.RUNNING:
			continue
		op.elapsed += delta
		if op.elapsed >= op.duration:
			_resolve(op)
			op.status = ActiveOperation.Status.COMPLETE
			operation_completed.emit(op.op_id)


# The one place resolution happens — unconditional and synchronous the
# instant _process detects completion, regardless of whether any UI is
# open to see it. Dispatches to whichever system actually owns the reward
# math (Research for Knowledge, Deposits for materials from Phase 5) rather
# than duplicating it here — Operations is the coordinator, not a second
# place Knowledge/materials get calculated.
func _resolve(op: ActiveOperation) -> void:
	op.result = Research.run_survey(op.activity_id)
