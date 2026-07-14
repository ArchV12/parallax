extends Node

# Session-scoped store of "what's currently locked in as the destination" —
# one id at a time, global (not tied to any one view/scene), same shape as
# Discoveries.gd. Deliberately independent of scanning — locking a
# destination doesn't require having scanned it first, and scanning
# something doesn't lock it (see the lock-destination design conversation
# in parallax-core-design-decisions memory). In-memory only for now, same
# caveat as Discoveries — no save system yet.

signal destination_changed

var locked_id: String = ""
# Real snapshot distance (km) to locked_id, captured the MOMENT it was
# locked, using whatever body the player is currently at and the live
# orbital angle data only System View has. -1.0 = no snapshot: either
# nothing is registered to provide one right now (see _snapshot_provider
# below), or it was locked somewhere with no live angle data (Planetary
# System View, where the existing real parent_distance_km math is already
# accurate and needs no override). TravelCalc.estimate uses this instead of
# its own radial-only approximation whenever it's set — see that function's
# own comment. Deliberately a locked-in snapshot, not something that keeps
# recalculating live while locked: unlock and relock later and it can come
# out different (the body's moved on) — a real strategy ("lock it right as
# it swings by for the shortest trip"), not an inconsistency to paper over.
var locked_distance_km: float = -1.0

# Set once by SystemView in its own _ready() (the only place with live
# orbital angle data to compute a real snapshot from) via
# set_snapshot_provider — Destination itself has no idea HOW to compute a
# distance, only that lock() must have the answer before anyone else can
# possibly ask for it (see lock()'s own comment on why this can't just be a
# destination_changed listener like everything else here). A Callable bound
# to a freed System View instance (scene change) naturally goes invalid —
# is_valid() below catches that and falls back to "no snapshot" rather than
# erroring, and the next System View load re-registers a fresh one.
var _snapshot_provider: Callable = Callable()

# Live (recomputed every frame, never frozen) distance to whatever's
# currently FOCUSED in System View — locked or not. Separate from
# locked_distance_km on purpose: that one is a deliberate one-time snapshot
# (the "lock it right as it swings by" strategy), while this is the running
# number that lets you actually watch for the good moment to lock in the
# first place. -1.0 = nothing to preview (nothing focused, or the current
# view has no live orbital data — see SystemView._update_callout/_exit_tree,
# the only writer). Plain fields rather than a Callable like
# _snapshot_provider: this is pushed every frame instead of pulled on
# demand, so there's no freed-instance staleness risk to guard against the
# same way — SystemView explicitly clears it on _exit_tree instead.
var preview_id: String = ""
var preview_distance_km: float = -1.0


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_preview(id: String, distance_km: float) -> void:
	preview_id = id
	preview_distance_km = distance_km


func clear_preview() -> void:
	preview_id = ""
	preview_distance_km = -1.0


func is_locked(id: String) -> bool:
	return locked_id == id


func has_destination() -> bool:
	return locked_id != ""


func lock(id: String) -> void:
	if locked_id == id:
		return
	locked_id = id
	# Computed synchronously HERE, before destination_changed even emits —
	# not from a listener reacting to that same signal. Every consumer
	# (ConsolePanel's readout included) connects to destination_changed
	# too, and Godot calls listeners in CONNECTION ORDER: ConsolePanel is
	# built by the HUD autoload at game boot, long before System View's own
	# listener could ever be connected, so it would ALWAYS run first and
	# read this while it was still unset if the snapshot were computed by a
	# listener instead — a real bug this shipped with briefly (readouts
	# silently showing the old radial approximation forever, since nothing
	# ever re-triggered a refresh after the correct value showed up a
	# moment too late).
	locked_distance_km = _snapshot_provider.call(id) if _snapshot_provider.is_valid() else -1.0
	destination_changed.emit()


func clear() -> void:
	if locked_id == "":
		return
	locked_id = ""
	locked_distance_km = -1.0
	destination_changed.emit()
