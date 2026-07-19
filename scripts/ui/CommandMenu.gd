class_name CommandMenu
extends Control

# The whole control surface, replacing the old six-pad ConsolePanel — a
# single small circular button, bottom-center, that on press draws six
# circuit-trace branches outward: each one fans out low, near the root
# button, then runs straight up in parallel to a chip evenly spaced along one
# tidy horizontal row above it. At rest almost nothing is on screen; the 3D
# view keeps the frame. HUD-global (not Cockpit-scene-local) — SYSTEM/CARGO/
# RESEARCH need to stay reachable from System/Planetary View too (see the
# plan's boot-sequencing/reachability findings), so CONSTRUCTION/SELL are
# the only entries actually gated to Cockpit, via
# set_cockpit_context() — outside Cockpit they're still visible but press
# plays a deny cue and does nothing, same "click no-ops, plays an error sfx"
# precedent the old ConsolePanel used for its unwired COMMAND/DATABASE pads.
#
# Data-driven (MENU below) rather than hand-placed per-item code — each
# chip's row position is computed procedurally from its array index/count, so
# adding/removing an entry (COMMAND/DATABASE, once they have real
# functionality) is a data edit only. A deliberately flat list, no hub/leaf
# hierarchy — an earlier version grouped ECONOMY/SYSTEM as branching hubs
# with their own sub-leaves, but that organic fan-of-different-radii shape
# read as messy rather than "in a system," and its shallow-angle leaf
# branches were also the two spots that kept catching a stray pixel of
# branch line poking past the chip's edge. A uniform row is both the cleaner
# look and the simpler geometry (every branch's final approach is a plain
# vertical segment, trivial to clear exactly).
#
# GO is deliberately absent — PlayerState.travel_to() is already reachable
# from SystemView/PlanetarySystemView's callout GO buttons and
# LocationsPanel's footer GO button; nothing here commits a trip.

# Emitted dynamically via emit_signal(entry["signal"]) below (see MENU's
# own "signal" string keys) — the analyzer can't trace a string-keyed
# emit_signal call back to these declarations, hence the ignores; every one
# of these five is genuinely wired up and used by HUD's own .connect() calls.
@warning_ignore("unused_signal")
signal system_pressed
@warning_ignore("unused_signal")
signal research_pressed
@warning_ignore("unused_signal")
signal cargo_pressed
@warning_ignore("unused_signal")
signal construction_pressed
@warning_ignore("unused_signal")
signal sell_pressed

# No OPERATIONS leaf anymore (Docs/Arrival Scan System.md) — Surveys
# auto-fire on arrival (ArrivalScanRow) and Mining's gateway opens directly
# from its own inline "Mine" button, so there's no drawer left to toggle.
const MENU: Array[Dictionary] = [
	{"id": "construction", "label": "CONSTRUCTION", "signal": "construction_pressed", "gated": true},
	{"id": "cargo", "label": "CARGO", "signal": "cargo_pressed"},
	{"id": "sell", "label": "SELL", "signal": "sell_pressed", "gated": true},
	{"id": "research", "label": "RESEARCH", "signal": "research_pressed"},
	{"id": "system", "label": "SYSTEM", "signal": "system_pressed"},
]

const ROOT_SIZE := 46.0
const ROOT_MARGIN_BOTTOM := 30.0
const ROW_Y_OFFSET := 190.0  # how far above the root button the row of chips sits
const ROW_WIDTH := 840.0     # total horizontal span the row is distributed across, centered on the root — spacing (ROW_WIDTH / (MENU.size() - 1)) must clear CHIP_SIZE.x with real room, or adjacent chips overlap
# Three-segment circuit-trace shape, all fractions of ROW_Y_OFFSET, shared by
# every branch so the whole fan reads as one consistent shape rather than six
# independently-angled lines: a short vertical STUB straight up from the root
# (every branch overlaps here, reads as a single trunk right at the button),
# then a diagonal run out to the chip's own x, then a final vertical RAIL
# straight up into the chip.
const STUB_FRAC := 0.12
const BEND_FRAC := 0.32
const CHIP_SIZE := Vector2(102.0, 28.0)  # uniform now — no more hub/leaf size distinction
const BRANCH_REVEAL_TIME := 0.28
# Per-item delay, left to right — a chip's own fade-in waits for its OWN
# branch to finish (see _expand's item_delay + BRANCH_REVEAL_TIME below,
# and _add_chip's .set_delay()) before it starts, so it can't appear before
# its line arrives. The "all chips pop at once" symptom this was briefly
# bumped up to work around turned out to be a real bug in how that delay was
# built (see _add_chip), not this value being too small — back to its
# original snappier pace now that the actual bug is fixed.
const ITEM_STAGGER_SEC := 0.05
const CHIP_FADE_TIME := 0.2
const RETRACT_TIME := 0.2
const GATED_DIM_ALPHA := 0.45

var _root_btn: Button
var _ring_time := 0.0
var _expanded := false
var _cockpit_context := true
var _live_nodes: Array[Node] = []  # every branch/chip built by _expand, torn down by _collapse


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_root_btn = Button.new()
	_root_btn.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_root_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_root_btn.size = Vector2(ROOT_SIZE, ROOT_SIZE)
	_root_btn.pressed.connect(func() -> void:
		AudioManager.ui_confirm("menu_slide")
		if _expanded:
			_collapse()
		else:
			_expand())
	add_child(_root_btn)

	resized.connect(_layout_root)
	_layout_root()


func _process(delta: float) -> void:
	_ring_time += delta
	queue_redraw()  # cheap single circle+ring draw, same "just poll every frame" precedent as ConsolePanel's own live readouts


func set_cockpit_context(active: bool) -> void:
	_cockpit_context = active


func _root_pos() -> Vector2:
	return Vector2(size.x * 0.5, size.y - ROOT_MARGIN_BOTTOM)


func _layout_root() -> void:
	_root_btn.position = _root_pos() - _root_btn.size * 0.5


func _draw() -> void:
	var center := _root_pos()
	var pulse := 0.5 + 0.3 * sin(_ring_time * 2.0)
	var ring_col: Color = UITheme.text
	ring_col.a = 0.15 + 0.1 * pulse
	draw_arc(center, ROOT_SIZE * 0.5 + 8.0, 0.0, TAU, 32, ring_col, 1.0)
	var core_col: Color = UITheme.text
	core_col.a = 0.45
	draw_arc(center, ROOT_SIZE * 0.5, 0.0, TAU, 32, core_col, 1.0)
	var glyph_col: Color = UITheme.text
	if _expanded:
		# rotated "X" — two crossed lines — instead of the idle horizontal dash
		draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), glyph_col, 1.4)
		draw_line(center + Vector2(-5, 5), center + Vector2(5, -5), glyph_col, 1.4)
	else:
		draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), glyph_col, 1.4)


# Evenly spaced across ROW_WIDTH, centered on the root's own x — index 0 is
# leftmost, index (count-1) is rightmost. A single-item MENU would divide by
# zero; not a real case here (six fixed entries), so left unguarded.
func _row_pos(root: Vector2, index: int, count: int) -> Vector2:
	var x := root.x - ROW_WIDTH * 0.5 + ROW_WIDTH * (float(index) / float(count - 1))
	return Vector2(x, root.y - ROW_Y_OFFSET)


# Exact distance from a box's own center to its edge, walking along
# `direction` (normalized) — NOT a flat radius. A flat radius under- or
# over-shoots depending on approach angle for a wide/short chip: clearing a
# shallow near-horizontal approach needs ~half the WIDTH, a steep near-
# vertical one only needs ~half the HEIGHT. This is the standard axis-
# aligned-box slab distance, so the branch clears the rect regardless of
# which angle it arrives from — moot now that every branch's final approach
# is a plain vertical segment (see BEND_FRAC), but kept general rather than
# special-cased to "vertical only," in case a future layout isn't as tidy.
func _distance_to_box_edge(direction: Vector2, box_size: Vector2) -> float:
	var half := box_size * 0.5
	var dx := absf(direction.x)
	var dy := absf(direction.y)
	if dx < 0.0001 and dy < 0.0001:
		return 0.0
	var t := INF
	if dx > 0.0001:
		t = minf(t, half.x / dx)
	if dy > 0.0001:
		t = minf(t, half.y / dy)
	return t


# Trims the branch's final segment so it stops just clear of `box_size` (the
# destination chip's own footprint, centered on the branch's endpoint) plus a
# small constant extra_gap for a clean visual break.
func _shorten_to(points: PackedVector2Array, box_size: Vector2, extra_gap: float = 4.0) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var last := points[points.size() - 1]
	var prev := points[points.size() - 2]
	var seg := last - prev
	var dist := seg.length()
	if dist <= 0.0:
		return points
	var dir := seg / dist
	var clear := _distance_to_box_edge(dir, box_size) + extra_gap
	if dist <= clear:
		return points
	var trimmed := points.duplicate()
	trimmed[trimmed.size() - 1] = last - dir * clear
	return trimmed


func _expand() -> void:
	_expanded = true
	queue_redraw()
	var root := _root_pos()
	# Both shared across every branch, not per-item, so the fan-out reads as
	# one consistent shape rather than six independently-angled lines.
	var stub_y := root.y - ROW_Y_OFFSET * STUB_FRAC
	var bend_y := root.y - ROW_Y_OFFSET * BEND_FRAC

	for i in MENU.size():
		var entry := MENU[i]
		var chip_pos := _row_pos(root, i, MENU.size())
		var stub := Vector2(root.x, stub_y)    # straight up from the root — every branch overlaps here
		var bend := Vector2(chip_pos.x, bend_y) # diagonal from the stub out to this chip's own x
		var points := PackedVector2Array([root, stub, bend, chip_pos])  # then straight up the rest of the way
		var item_delay := i * ITEM_STAGGER_SEC

		_add_branch(_shorten_to(points, CHIP_SIZE), item_delay)
		_add_chip(entry, chip_pos, item_delay + BRANCH_REVEAL_TIME)


func _add_branch(points: PackedVector2Array, start_delay: float) -> void:
	var branch := CommandMenuBranch.new()
	branch.points = points
	branch.stroke_color = UITheme.accent
	add_child(branch)
	_live_nodes.append(branch)

	var tw := create_tween()
	if start_delay > 0.0:
		tw.tween_interval(start_delay)
	tw.tween_property(branch, "reveal", 1.0, BRANCH_REVEAL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _add_chip(entry: Dictionary, point: Vector2, start_delay: float) -> void:
	var gated: bool = entry.get("gated", false)

	var chip := UIButton.new()
	chip.text = entry["label"]
	# solid, not accent — accent's chamfered-hexagon fill is deliberately
	# glassy/translucent (tuned for a single hero CTA like Main Menu's NEW
	# GAME over a busy 3D backdrop), which on a dense six-chip cluster read as
	# "no background at all." solid reuses the same near-opaque dark panel
	# style ConsolePadButton (this class's predecessor) and GO/LOCK/SELL
	# elsewhere already use — a plain rect with corner brackets instead of
	# the hex/glow shape, but a known-good look rather than re-tuning
	# accent's gradient and risking another regression there.
	chip.solid = true
	chip.shimmer_enabled = false  # dense cluster, a moving sweep on every chip at once reads as noise — same ConsolePadButton precedent
	chip.press_sfx = ""  # this class plays its own confirm/deny cue below, see _on_chip_pressed
	chip.add_theme_font_size_override("font_size", 11)
	chip.size = CHIP_SIZE
	chip.position = point - CHIP_SIZE * 0.5
	chip.modulate.a = 0.0
	chip.scale = Vector2(0.4, 0.4)
	chip.pivot_offset = CHIP_SIZE * 0.5
	chip.pressed.connect(_on_chip_pressed.bind(entry))
	add_child(chip)
	_live_nodes.append(chip)

	# .set_delay() on each tweener directly, NOT a leading tween_interval() —
	# that worked fine in _add_branch (one sequential tweener, nothing else
	# competing with it) but a leading interval feeding into a set_parallel(true)
	# group of two tweeners here didn't reliably delay the group the same way.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(chip, "modulate:a", (GATED_DIM_ALPHA if (gated and not _cockpit_context) else 1.0), CHIP_FADE_TIME).set_delay(start_delay)
	tw.tween_property(chip, "scale", Vector2.ONE, CHIP_FADE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(start_delay)


func _on_chip_pressed(entry: Dictionary) -> void:
	var gated: bool = entry.get("gated", false)
	if gated and not _cockpit_context:
		AudioManager.ui_deny()
		return
	AudioManager.ui_confirm()
	_collapse()
	emit_signal(entry["signal"])


func _collapse() -> void:
	_expanded = false
	queue_redraw()
	var nodes := _live_nodes.duplicate()
	_live_nodes.clear()
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var tw := create_tween()
		tw.set_parallel(true)
		if node is CommandMenuBranch:
			tw.tween_property(node, "reveal", 0.0, RETRACT_TIME)
		else:
			tw.tween_property(node, "modulate:a", 0.0, RETRACT_TIME)
			tw.tween_property(node, "scale", Vector2(0.4, 0.4), RETRACT_TIME)
		tw.finished.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free())
