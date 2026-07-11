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


func is_locked(id: String) -> bool:
	return locked_id == id


func has_destination() -> bool:
	return locked_id != ""


func lock(id: String) -> void:
	if locked_id == id:
		return
	locked_id = id
	destination_changed.emit()


func clear() -> void:
	if locked_id == "":
		return
	locked_id = ""
	destination_changed.emit()
