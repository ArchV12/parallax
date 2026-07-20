extends Node

# Session-scoped store of "what has the player navigationally revealed" —
# id -> tier. Deliberately generic (not planet-specific): any scannable
# thing (a body's data panel; moons, surface features, signals, ... later)
# shares this one primitive rather than each inventing its own local "have
# I found this already" flag. In-memory only for now since there's no save
# system yet (see PauseMenu's still-stub Save button) — swapping this to
# read/write an actual save file later is a backend change behind the same
# interface, not a redesign.
#
# 2026-07-19 — this flag now means TWO things at once, on purpose, not two
# separate flags: "does this body exist as far as the player knows" (does
# it render as a real body vs. an unidentified blip) AND "is its
# BodyInfoPanel data available" (no separate animated per-target SCAN step
# anymore — see NavScan.gd). The two used to be different mechanisms
# (SystemView's old min_nav_tier gate for existence, this dict + ScanPrompt/
# BodyInfoPanel's own scan animation for data) but collapsed into one once
# Nav Scan existed: if a scan found the body at all, it already has enough
# of a read on it to show the data panel too. mark_scanned() is now called
# by NavScan.resolve() instead of BodyInfoPanel._finish_scan() — same dict,
# different writer. PlanetarySystemView.gd's own moon-scan flow still uses
# the OLD per-target animation (untouched this pass — no non-Sol system has
# any moons yet to exercise it either way).
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


# Every Sol-system body (every curated planet/moon, and any asteroid already
# spawned/registered this session) starts pre-scanned by default — Docs/Ship
# Equipment.md's "Sol system exception": the game starts in 2037, so
# humanity already has complete navigational/data knowledge of its own solar
# system. This isn't a placeholder, it's a permanent fact about Sol
# specifically — same reasoning NavScan.gd's radius check already applies
# (Sol bodies never need a scan to reveal at all, so the check never runs
# for them in practice).
#
# 2026-07-19 fix: this used to just check "does KnownBodies.get_entry(id)
# resolve at all" — true when written (KnownBodies really was Sol-only
# then), but broke the instant Proxima Centauri's bodies joined the SAME
# catalog. A foreign body now resolving through get_entry() too meant it
# ALSO came out pre-scanned the moment Navigation Scanner let it render —
# no SCAN button, no scanning animation, data just there immediately, same
# as Earth. That's backwards: Sol is the one deliberate exception, not the
# default every other system inherits by accident of sharing a lookup
# function. Now explicitly keyed on entry.star_system == "Sol" — a foreign
# body (Proxima b, or any future non-Sol system) genuinely starts
# unscanned, giving arrival there a real "SCAN this" moment instead of
# skipping straight to data.
#
# NOTE: this is deliberately independent of Scanner Array/Research survey
# state — a body being navigationally known (it exists, you can see its
# stats, you can fly there) says nothing about whether it's been
# resource/geological-surveyed. That still requires owning the right
# Scanner Array tier and running an actual survey.
func scan_tier(id: String) -> Tier:
	if _scans.has(id):
		return _scans[id]
	var entry := KnownBodies.get_entry(id)
	if entry != null and entry.star_system == "Sol":
		return Tier.SCANNED
	return Tier.NONE


func mark_scanned(id: String, tier: Tier = Tier.SCANNED) -> void:
	_scans[id] = tier


# See PlayerState.reset_for_new_game — same "autoloads outlive the scene"
# problem, applied here.
func reset_for_new_game() -> void:
	_scans = {}
