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
# probes/ships working elsewhere) is an extension, not a rewrite. Concurrency
# is enforced per KIND, not globally (see can_start/has_running_mining/
# has_running_survey) — Mining runs on its own dedicated system (the mining
# laser) and doesn't compete with a Survey for the ship's attention, so the
# two run independently; you still can't run two Surveys at once (one sensor
# suite) or mine two deposits at once (one laser).

signal operation_started(op_id: String)
# Fired AFTER resolution has already run (op.result is populated) — see
# _resolve. Survey-kind only — mining never reaches this (see
# operation_stopped below). Consumers never need to call anything to
# "finish" an operation; it's already fully resolved by the time they hear
# about it.
signal operation_completed(op_id: String)
signal operation_dismissed(op_id: String)
# Mining-kind only — fired the instant a continuous mining operation ends,
# for any of the four reasons ("stopped"/"departed"/"depleted"/"cargo_full"
# — see _finish_mining). Carries a summary directly rather than an op_id, since
# the ActiveOperation is already erased from _operations by the time this
# fires (there's nothing left to view — everything in summary was already
# committed to Deposits' inventory as it ticked, unlike a survey's deferred
# "See Results").
signal operation_stopped(activity_id: String, location_id: String, summary: Dictionary)

var _operations: Dictionary = {}  # op_id -> ActiveOperation
var _next_op_id: int = 0


func _ready() -> void:
	# Mining only makes sense while the ship is actually AT the body being
	# mined (per the user's own framing: "the deposit is right there") — the
	# instant departure begins is the correct stop point, not arrival at the
	# new destination, since the ship is no longer at the old body from that
	# moment on.
	PlayerState.travel_started.connect(_on_travel_started)


func _on_travel_started() -> void:
	var op := operation_for_activity("mining")
	if op != null and op.status == ActiveOperation.Status.RUNNING:
		_finish_mining(op, "departed")


# Whether THIS KIND of activity could start right now — Mining and Survey
# are independent tracks (see class comment), so starting a Survey is only
# ever blocked by another RUNNING Survey, never by Mining being active, and
# vice versa. Also only checks for a RUNNING operation of that track, not
# "any operation at all" — COMPLETE-but-undismissed Surveys must NOT block
# starting a new one (results are meant to be viewed whenever the player
# gets around to it, per the passive "COMPLETED — See Results / X" design;
# blocking new work on an unacknowledged old result would contradict that).
func can_start(activity_id: String) -> bool:
	if activity_id == "mining":
		return not has_running_mining()
	return not has_running_survey()


func has_running_mining() -> bool:
	var op := operation_for_activity("mining")
	return op != null and op.status == ActiveOperation.Status.RUNNING


func has_running_survey() -> bool:
	for op: ActiveOperation in _operations.values():
		if op.activity_id != "mining" and op.status == ActiveOperation.Status.RUNNING:
			return true
	return false


# Just one of possibly several COMPLETE-undismissed Surveys (see can_start's
# comment) — a convenience for callers that don't care WHICH one, not what
# ActivitiesPanel's own per-activity row building uses (that goes through
# operation_for_activity instead).
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
	var def := Research.activity_def(activity_id)
	op.flavor_duration_seconds = def.flavor_duration_seconds if def != null else 0
	_operations[op.op_id] = op
	operation_started.emit(op.op_id)
	return op.op_id


# Mining's counterpart to start_survey — always for exactly one material at
# a time (never "extract everything"), per the deliberate gameplay choice
# this is. Continuous, not a single resolve step (see _tick_mining) — there
# is no yield to roll or duration to set up front, both emerge tick by tick.
# Returns "" if the deposit doesn't exist, or if the cargo hold is already
# full (both defensive only — DepositDetailPanel.open_for already wouldn't
# have offered a usable BEGIN EXTRACTION for either case; see its own
# ship_busy/is_cargo_full handling).
func start_mining(body_id: String, material_name: String) -> String:
	var deposit := Deposits.deposit_for(body_id, material_name)
	if deposit == null or Deposits.is_cargo_full():
		return ""
	var op := ActiveOperation.new()
	_next_op_id += 1
	op.op_id = str(_next_op_id)
	op.activity_id = "mining"
	op.location_id = body_id
	op.deposit_material = material_name
	_operations[op.op_id] = op
	operation_started.emit(op.op_id)
	return op.op_id


# Player-initiated stop — one of the three ways a continuous mining
# operation ends (see _finish_mining). No-ops for anything that isn't a
# RUNNING mining operation (defensive only — the STOP button only exists on
# a mining operation's own active card).
func stop_mining(op_id: String) -> void:
	var op := get_operation(op_id)
	if op == null or op.activity_id != "mining" or op.status != ActiveOperation.Status.RUNNING:
		return
	_finish_mining(op, "stopped")


# Removes a COMPLETE operation without ever having shown its results —
# no-ops silently for a RUNNING op (nothing should be able to dismiss work
# still in progress; cancellation, if ever added, is a different action).
# Survey-kind only — mining never reaches COMPLETE (see operation_stopped).
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
		if op.activity_id == "mining":
			_tick_mining(op, delta)
			continue
		op.elapsed += delta
		if op.elapsed >= op.duration:
			_resolve(op)
			op.status = ActiveOperation.Status.COMPLETE
			operation_completed.emit(op.op_id)


# The one place survey resolution happens — unconditional and synchronous
# the instant _process detects completion, regardless of whether any UI is
# open to see it. Dispatches to Research (the system that actually owns
# Knowledge math) rather than duplicating it here — Operations is the
# coordinator, not a second place it gets calculated.
func _resolve(op: ActiveOperation) -> void:
	op.result = Research.run_survey(op.activity_id, op.location_id)


# One continuous-mining tick's worth of progress, called every frame while
# a mining operation is RUNNING. Clamps this tick's effective delta to
# whichever comes first — the deposit hitting 0%, or the cargo hold hitting
# CARGO_CAPACITY (see Deposits.cargo_space_remaining) — so a single large
# delta (a lag spike, or just bad luck on frame timing) can never overshoot
# past either limit. Fractional yield accumulates on the operation itself
# (mining_yield_accumulator) and is only committed to Deposits' inventory
# once it crosses a whole-unit boundary — the player's inventory should only
# ever hold whole numbers, but depletion itself stays smooth every frame
# regardless of where that boundary falls.
func _tick_mining(op: ActiveOperation, delta: float) -> void:
	var deposit := Deposits.deposit_for(op.location_id, op.deposit_material)
	if deposit == null or deposit.remaining_fraction <= 0.0:
		_finish_mining(op, "depleted")
		return
	var space := Deposits.cargo_space_remaining()
	if space <= 0:
		_finish_mining(op, "cargo_full")
		return

	var depletion_rate := Deposits.depletion_rate_per_second(deposit)
	var extraction_rate := Deposits.extraction_rate_per_second(deposit)
	var time_to_deplete := deposit.remaining_fraction / depletion_rate
	# How much longer, at this rate, before the remaining cargo space fills —
	# nets out mining_yield_accumulator's already-banked fractional progress
	# toward the next whole unit, so this doesn't overstate the time left by
	# up to a whole extra unit's worth.
	var time_to_fill_cargo := (float(space) - op.mining_yield_accumulator) / extraction_rate
	var actual_delta := minf(delta, minf(time_to_deplete, time_to_fill_cargo))

	var fraction_delta := depletion_rate * actual_delta
	op.mining_yield_accumulator += extraction_rate * actual_delta
	var whole_units := int(op.mining_yield_accumulator)
	if whole_units > 0:
		op.mining_yield_accumulator -= whole_units
		op.mining_session_yield += whole_units
	Deposits.extract_tick(op.location_id, op.deposit_material, whole_units, fraction_delta)

	if actual_delta >= time_to_fill_cargo:
		_finish_mining(op, "cargo_full")
	elif actual_delta >= time_to_deplete:
		_finish_mining(op, "depleted")


# The one place a mining operation actually ends, for any of the four
# reasons (player-initiated stop_mining, departure — see _on_travel_started,
# hitting 0% remaining, or hitting CARGO_CAPACITY — both in _tick_mining).
# Erases it immediately rather than moving it to a COMPLETE-awaiting-dismiss
# state — there's nothing left to view, everything in summary was already
# committed to Deposits' inventory as it ticked (see _tick_mining).
func _finish_mining(op: ActiveOperation, reason: String) -> void:
	var summary := {
		"material_name": op.deposit_material,
		"amount_awarded": op.mining_session_yield,
		"reason": reason,  # "stopped" / "departed" / "depleted" / "cargo_full"
	}
	_operations.erase(op.op_id)
	operation_stopped.emit(op.activity_id, op.location_id, summary)
