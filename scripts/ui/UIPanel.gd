class_name UIPanel
extends PanelContainer

# HUD-styled panel container — the panel-scale sibling of UIButton's accent
# style: a chamfered hexagon (top-left/bottom-right corners cut, matching
# the button shape language), a layered glow border, a subtle top-lighter
# vertical gradient fill, and segmented tick marks along the two straight
# edges. open_animated()/close_animated() handle the scale+fade "power on"
# and semantic audio.
#
# Deliberately no shimmer sweep here (unlike UIButton) — panels carry actual
# information (sliders, labels, readouts), and a moving highlight competed
# with reading the content. Shimmer stays a button-only "look at me" cue.
#
# The visible background is entirely hand-drawn in _draw() — the "panel"
# StyleBox slot only carries a StyleBoxEmpty so PanelContainer still insets
# its child via content margins, without drawing a rect underneath our shape.

const CHAMFER_FRAC := 0.10   # corner cut, as a fraction of the shorter side
const CHAMFER_MIN := 12.0
const CHAMFER_MAX := 28.0
const TICK_SPACING := 26.0
const TICK_LEN := 6.0
const ANIM_TIME := 0.16


func _ready() -> void:
	_apply_style()
	UITheme.theme_changed.connect(_apply_style)
	resized.connect(_on_resized)


func _apply_style() -> void:
	# Invisible — only here so PanelContainer still insets its child by these
	# margins. The visible fill/border is drawn in _draw() instead.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 20
	empty.content_margin_right = 20
	empty.content_margin_top = 18
	empty.content_margin_bottom = 16
	add_theme_stylebox_override("panel", empty)
	queue_redraw()


func _chamfer_amount() -> float:
	return clampf(minf(size.x, size.y) * CHAMFER_FRAC, CHAMFER_MIN, CHAMFER_MAX)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _draw() -> void:
	var c := _chamfer_amount()
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(0, h), Vector2(0, c),
	])

	var base: Color = UITheme.panel
	var top_col := base.lightened(0.1)
	top_col.a = 0.88
	var bot_col := base
	bot_col.a = 0.88
	# Vertex order: top(ish), top-right, right, bottom(ish), bottom-left, left.
	var colors := PackedColorArray([top_col, top_col, bot_col, bot_col, bot_col, top_col])
	draw_polygon(pts, colors)

	var loop := pts.duplicate()
	loop.append(pts[0])
	var halo := UITheme.accent.darkened(0.5)
	halo.a = 0.5
	draw_polyline(loop, halo, 5.0, true)
	var core := UITheme.accent
	core.a = 0.85
	draw_polyline(loop, core, 2.0, true)

	var tick_col := UITheme.accent
	tick_col.a = 0.7
	_draw_ticks(w, h, c, tick_col)


# Small perpendicular dashes along the top and bottom straight edges — the
# "instrument panel" detailing from the reference images. Skipped on the two
# chamfered diagonals to avoid the extra geometry of walking their angle.
func _draw_ticks(w: float, h: float, c: float, col: Color) -> void:
	var x := c + TICK_SPACING * 0.5
	while x < w - 4.0:
		draw_line(Vector2(x, -TICK_LEN * 0.5), Vector2(x, TICK_LEN * 0.5), col, 1.5)
		x += TICK_SPACING
	x = 4.0
	while x < w - c - 4.0:
		draw_line(Vector2(x, h - TICK_LEN * 0.5), Vector2(x, h + TICK_LEN * 0.5), col, 1.5)
		x += TICK_SPACING


# Shows the panel with a quick scale+fade "power on" and a matching sound.
# Callers that need to intercept clicks on a full-screen backdrop should
# still manage that Control's own visibility separately — this only
# animates the panel itself.
func open_animated() -> void:
	visible = true
	pivot_offset = size * 0.5
	scale = Vector2(0.94, 0.94)
	modulate.a = 0.0
	AudioManager.ui_panel_open()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, ANIM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, ANIM_TIME)


func close_animated() -> void:
	AudioManager.ui_panel_close()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), ANIM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, ANIM_TIME)
	tw.chain().tween_callback(func() -> void: visible = false)


# Builds a "TITLE" + divider header — the standard data-card heading, meant
# to be the first child added to a UIPanel's own content VBoxContainer.
# Static so a screen can grab it without needing a UIPanel instance around.
static func build_title_header(title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", UITheme.accent)
	box.add_child(lbl)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.5)
	box.add_child(divider)

	return box
