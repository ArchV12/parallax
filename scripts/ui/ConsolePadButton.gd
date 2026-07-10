class_name ConsolePadButton
extends Control

# A console button shaped as a trapezoid slice of the console's own
# silhouette — a straight top edge slanting between two heights, flush
# bottom/left/right — so a row of these butted together exactly tiles the
# console's wing with no gaps and no panel background showing between or
# around them. Not a Button: the slanted, non-rectangular hit area needs a
# custom _has_point() override (Control supports this directly), which
# doesn't combine cleanly with Button's own StyleBox-driven hit rect.
#
# No scale-pop on hover (unlike UIButton) — these sit flush against their
# neighbors with zero gap, so scaling up would visibly overlap the button
# next door. Hover instead just brightens the fill/border in place.

signal pressed

const BRACKET_LEN_FRAC := 0.22
const BRACKET_MIN := 10.0
const BRACKET_MAX := 26.0
const BRACKET_MARGIN := 3.0

var top_left: float = 0.0   # local-space y of the top edge at x = 0
var top_right: float = 0.0  # local-space y of the top edge at x = size.x
var label_text: String = "" : set = set_label_text

var _hovered := false
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_label = Label.new()
	_label.text = label_text
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", UITheme.text)
	add_child(_label)

	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	resized.connect(_layout_label)
	UITheme.theme_changed.connect(_on_theme_changed)
	_layout_label()


func set_label_text(value: String) -> void:
	label_text = value
	if _label != null:
		_label.text = value


func set_top_edge(tl: float, tr: float) -> void:
	top_left = tl
	top_right = tr
	_layout_label()
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	if point.x < 0.0 or point.x > size.x or point.y < 0.0 or point.y > size.y:
		return false
	var t: float = point.x / maxf(size.x, 0.001)
	return point.y >= lerpf(top_left, top_right, t)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			AudioManager.ui_confirm()
			pressed.emit()


func _on_hover() -> void:
	_hovered = true
	AudioManager.ui_hover()
	queue_redraw()


func _on_unhover() -> void:
	_hovered = false
	queue_redraw()


func _on_theme_changed() -> void:
	_label.add_theme_color_override("font_color", UITheme.text)
	queue_redraw()


# Centers the label between the taller of the two top-edge heights and the
# bottom — keeps it clear of the narrow tip so it never pokes above the roof.
func _layout_label() -> void:
	if _label == null:
		return
	var constraining_top: float = maxf(top_left, top_right)
	var mid_y: float = (constraining_top + size.y) * 0.5
	_label.size = Vector2(size.x, _label.get_minimum_size().y)
	_label.position = Vector2(0.0, mid_y - _label.size.y * 0.5)


func _draw() -> void:
	var pts := PackedVector2Array([
		Vector2(0.0, top_left), Vector2(size.x, top_right),
		Vector2(size.x, size.y), Vector2(0.0, size.y),
	])
	# Light-top/dark-bottom gradient via per-vertex polygon colors — same
	# trick UIButton's accent shape uses — instead of a flat fill, so the pad
	# reads as machined material catching light rather than a plain color
	# swatch.
	var base: Color = UITheme.button_hov if _hovered else UITheme.button
	var light := base.lightened(0.35)
	var dark := base.darkened(0.35)
	light.a = 0.97
	dark.a = 0.97
	draw_polygon(pts, PackedColorArray([light, light, dark, dark]))

	# Thin bevel catch-light just under the top edge, like a machined panel
	# lip.
	var bevel := Color(1.0, 1.0, 1.0, 0.22 if _hovered else 0.10)
	var inset := 4.0
	draw_line(Vector2(3.0, top_left + inset), Vector2(size.x - 3.0, top_right + inset), bevel, 1.0)

	# Corner angle brackets, same inset-L language as UIButton's plain style —
	# but the top two follow the actual slanted top edge instead of a fixed
	# horizontal, so they hug the panel's real angle at this pad's position
	# rather than sitting crooked against it.
	var bracket_col: Color = (UITheme.accent if _hovered else UITheme.border).lightened(0.45)
	bracket_col.a = 0.9 if _hovered else 0.6
	var bw := 2.2 if _hovered else 1.5
	var arm := clampf(minf(size.x, size.y) * BRACKET_LEN_FRAC, BRACKET_MIN, BRACKET_MAX)
	var top_dir := Vector2(size.x, top_right - top_left).normalized() if size.x > 0.0 else Vector2.RIGHT
	_draw_bracket(Vector2(0.0, top_left), top_dir, Vector2.DOWN, arm, bracket_col, bw)
	_draw_bracket(Vector2(size.x, top_right), -top_dir, Vector2.DOWN, arm, bracket_col, bw)
	_draw_bracket(Vector2(0.0, size.y), Vector2.UP, Vector2.RIGHT, arm, bracket_col, bw)
	_draw_bracket(Vector2(size.x, size.y), Vector2.UP, Vector2.LEFT, arm, bracket_col, bw)

	var border: Color = UITheme.accent if _hovered else UITheme.border
	border.a = 0.9 if _hovered else 0.5
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, border, 2.0 if _hovered else 1.0, true)


# Draws an inset L-bracket at `corner`, with each arm following its own
# direction vector — dir_a/dir_b need not be axis-aligned, so this covers
# both the ordinary right-angle bottom corners and the top corners, where
# one arm has to follow the panel's slant instead of a fixed horizontal.
func _draw_bracket(corner: Vector2, dir_a: Vector2, dir_b: Vector2, arm: float, col: Color, width: float) -> void:
	var base_pt := corner + dir_a * BRACKET_MARGIN + dir_b * BRACKET_MARGIN
	draw_line(base_pt, base_pt + dir_a * arm, col, width)
	draw_line(base_pt, base_pt + dir_b * arm, col, width)
