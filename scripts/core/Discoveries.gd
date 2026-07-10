extends Node

# Session-scoped store of "what has the player scanned" — id -> tier.
# Deliberately generic (not planet-specific): any scannable thing (a body's
# data panel today; moons, surface features, signals, ... later) shares this
# one primitive rather than each inventing its own local "have I scanned
# this already" flag. In-memory only for now since there's no save system
# yet (see PauseMenu's still-stub Save button) — swapping this to read/write
# an actual save file later is a backend change behind the same interface,
# not a redesign.
#
# Tiers exist so "how much detail a scan reveals" can grow later (tied to
# scanner tech level, per the scanning design conversation in
# parallax-core-design-decisions memory) without changing this interface —
# only NONE/SCANNED are used today.

enum Tier { NONE, SCANNED }

var _scans: Dictionary = {}  # id -> Tier


func is_scanned(id: String) -> bool:
	return scan_tier(id) != Tier.NONE


func scan_tier(id: String) -> Tier:
	return _scans.get(id, Tier.NONE)


func mark_scanned(id: String, tier: Tier = Tier.SCANNED) -> void:
	_scans[id] = tier
