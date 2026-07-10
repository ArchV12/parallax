class_name ConsolePanel
extends Control

# The cockpit's always-on instrument console — a flat center band (reserved
# for context-free readouts; nothing view-specific ever renders here) flanked
# by two wings that taper down toward the screen edges. Each wing is tiled
# edge-to-edge, with zero gap, by big ConsolePadButtons individually shaped
# to match the wing's slanted silhouette at their position — the console's
# entire visible surface outside the center band IS the buttons; none of
# the panel's own translucent fill ever shows through beside or around one.
# Anything context-dependent (mining, crafting, ...) is a separate popup
# layered on top, never absorbed into this shape — see the cockpit-console
# design conversation in parallax-core-design-decisions memory.
#
# Read left to right: SYSTEM, GO, SCAN on the left wing (SCAN sits against
# the center bend, so it's automatically the tallest/biggest of the three);
# COMMAND, RESEARCH, DATABASE on the right (mirrored — COMMAND against the
# bend). GO/SCAN/COMMAND/RESEARCH/DATABASE have no systems behind them yet —
# left fully interactive (hover/press feedback) rather than disabled, they
# just have nothing connected to `pressed`, so a click no-ops. GO is meant
# to become the travel-commit action once a destination can be plotted
# somewhere (System view and later scopes) — it does NOT switch views itself;
# that's ViewSwitcher.gd's job now (see the view-switcher conversation in
# parallax-core-design-decisions memory).

signal system_pressed

const HEIGHT_CENTER := 150.0
const HEIGHT_EDGE := 56.0
const CENTER_WIDTH_MAX := 620.0
const CENTER_WIDTH_FRAC := 0.42
const EDGE_HALO_WIDTH := 6.0
const EDGE_CORE_WIDTH := 1.5

const LEFT_LABELS := ["SYSTEM", "GO", "SCAN"]
const RIGHT_LABELS := ["COMMAND", "RESEARCH", "DATABASE"]

var _left_buttons: Array[ConsolePadButton] = []
var _right_buttons: Array[ConsolePadButton] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -HEIGHT_CENTER
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for label in LEFT_LABELS:
		var btn := _make_pad(label)
		_left_buttons.append(btn)
		add_child(btn)
	for label in RIGHT_LABELS:
		var btn := _make_pad(label)
		_right_buttons.append(btn)
		add_child(btn)

	_left_buttons[0].pressed.connect(func() -> void: system_pressed.emit())

	resized.connect(_layout_buttons)
	UITheme.theme_changed.connect(queue_redraw)
	_layout_buttons()


func _make_pad(label: String) -> ConsolePadButton:
	var btn := ConsolePadButton.new()
	btn.label_text = label
	return btn


func _center_half_width() -> float:
	return minf(CENTER_WIDTH_MAX, size.x * CENTER_WIDTH_FRAC) * 0.5


# Top-edge height at a given x within the LEFT wing's diagonal, which runs
# from (0, h - HEIGHT_EDGE) up to (x0, 0) at the center bend.
func _left_edge_y(x: float, x0: float, h: float) -> float:
	if x0 <= 0.0:
		return h - HEIGHT_EDGE
	return lerpf(h - HEIGHT_EDGE, 0.0, clampf(x / x0, 0.0, 1.0))


# Mirror of the above for the RIGHT wing's diagonal, from (x1, 0) at the
# bend out to (w, h - HEIGHT_EDGE) at the screen edge.
func _right_edge_y(x: float, x1: float, w: float, h: float) -> float:
	if w <= x1:
		return 0.0
	return lerpf(0.0, h - HEIGHT_EDGE, clampf((x - x1) / (w - x1), 0.0, 1.0))


func _layout_buttons() -> void:
	var h := size.y
	var half := _center_half_width()
	var x0 := size.x * 0.5 - half
	var x1 := size.x * 0.5 + half

	var count := _left_buttons.size()
	for i in count:
		var xa := x0 * (float(i) / count)
		var xb := x0 * (float(i + 1) / count)
		var btn := _left_buttons[i]
		btn.position = Vector2(xa, 0.0)
		btn.size = Vector2(xb - xa, h)
		btn.set_top_edge(_left_edge_y(xa, x0, h), _left_edge_y(xb, x0, h))

	var rcount := _right_buttons.size()
	for i in rcount:
		var xa := x1 + (size.x - x1) * (float(i) / rcount)
		var xb := x1 + (size.x - x1) * (float(i + 1) / rcount)
		var btn := _right_buttons[i]
		btn.position = Vector2(xa, 0.0)
		btn.size = Vector2(xb - xa, h)
		btn.set_top_edge(_right_edge_y(xa, x1, size.x, h), _right_edge_y(xb, x1, size.x, h))

	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var half := _center_half_width()
	var x0 := w * 0.5 - half
	var x1 := w * 0.5 + half

	# Only the center band's own fill is drawn here — the wings are fully
	# tiled by pad buttons on top, so painting fill under them would never
	# actually be seen.
	var fill: Color = UITheme.panel
	fill.a = 0.92
	draw_colored_polygon(PackedVector2Array([
		Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, h), Vector2(x0, h),
	]), fill)

	var edge := PackedVector2Array([
		Vector2(0.0, h - HEIGHT_EDGE), Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(w, h - HEIGHT_EDGE),
	])
	var halo: Color = UITheme.accent
	halo.a = 0.35
	draw_polyline(edge, halo, EDGE_HALO_WIDTH, true)
	draw_polyline(edge, UITheme.accent, EDGE_CORE_WIDTH, true)
