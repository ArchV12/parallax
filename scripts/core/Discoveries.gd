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

# id -> Tier, explicit overrides only. Sol-system bodies default to SCANNED
# without needing an entry here at all (see scan_tier below) — this dict now
# only exists for anything that deliberately does NOT get that default.
var _scans: Dictionary = {}


func is_scanned(id: String) -> bool:
	return scan_tier(id) != Tier.NONE


# Every body KnownBodies.get_entry() recognizes (every curated planet/moon,
# and any asteroid already spawned/registered this session) is a Sol-system
# body. Docs/Ship Equipment.md's "Sol system exception": the game starts in
# 2037, so humanity already has complete navigational/data knowledge of its
# own solar system — this isn't a placeholder, it's a permanent fact about
# Sol specifically. So any such body starts pre-scanned by default, same as
# Earth/Luna used to be hardcoded here, just generalized to the whole
# catalog instead of two names. A future non-Sol system's bodies won't
# resolve via KnownBodies (a Sol-only catalog) and correctly fall through to
# NONE here, unscanned, without this needing to change later.
#
# NOTE: this is deliberately independent of Scanner Array/Research survey
# state — a body being navigationally known (it exists, you can see its
# stats, you can fly there) says nothing about whether it's been
# resource/geological-surveyed. That still requires owning the right
# Scanner Array tier and running an actual survey.
func scan_tier(id: String) -> Tier:
	if _scans.has(id):
		return _scans[id]
	if KnownBodies.get_entry(id) != null:
		return Tier.SCANNED
	return Tier.NONE


func mark_scanned(id: String, tier: Tier = Tier.SCANNED) -> void:
	_scans[id] = tier


# See PlayerState.reset_for_new_game — same "autoloads outlive the scene"
# problem, applied here.
func reset_for_new_game() -> void:
	_scans = {}
