class_name UIButton
extends Button

# HUD-styled button: translucent glass fill, an idle shimmer sweep, and
# semantic hover/press audio. The shared building block every screen should
# reach for instead of hand-rolling Button.new() + UITheme.style_button().
#
# Two looks, chosen by `accent`:
#  - Plain (accent = false): a simple translucent rect with drawn corner
#    brackets — cheap, quiet, for secondary/utility actions.
#  - Accent (accent = true): a chamfered hexagon with a layered glowing
#    border and a vertical gradient fill, replacing the rect StyleBox
#    entirely (see _apply_style — accent buttons get a StyleBoxEmpty so the
#    custom _draw() polygon is the only visible background). Reserved for
#    primary/CTA actions (New Game, Generate) — the "killer UI" showpiece.
#
# Hover is deliberately a big, unmissable jump (scale pop + faster/brighter
# shimmer + bolder border), not a subtle alpha nudge.

const SHIMMER_SHADER := preload("res://shaders/ui_shimmer.gdshader")

const BRACKET_LEN_FRAC := 0.22  # corner bracket arm length, as a fraction of the shorter side
const BRACKET_MARGIN := 3.0
const CHAMFER_FRAC := 0.32      # accent shape's corner cut, as a fraction of button height

const SHIMMER_IDLE := 0.2
const SHIMMER_HOVER := 0.3
const SHIMMER_SPEED_IDLE := 0.5
const SHIMMER_SPEED_HOVER := 1.7
const HOVER_SCALE := 1.07
const HOVER_ANIM_TIME := 0.12

@export var accent: bool = false  # true = primary/CTA styling (chamfered shape + gradient + glow border)
@export var dim: bool = false     # true = de-emphasized text (secondary/utility actions)
# true = near-opaque fill instead of the plain style's translucent glass —
# for a plain button that needs to stay readable over whatever's behind it
# (e.g. floating over a 3D scene where "behind" might be a bright planet or
# the sun itself), where translucency defeats the point. No effect on
# accent buttons, which are already a solid gradient fill.
@export var solid: bool = false
# false = skip the idle/hover sweep — the scale-pop and border/fill brighten
# in _draw_accent_shape/_draw_bracket_frame (both keyed off is_hovered(),
# independent of the shimmer) still provide a hover "light up" on their own.
# Off for dense button clusters (the cockpit console) where a moving sweep
# on every button at once reads as noisy rather than alive.
@export var shimmer_enabled: bool = true

var _shimmer: ColorRect
var _shimmer_mat: ShaderMaterial


func _ready() -> void:
	_apply_style()
	if shimmer_enabled:
		_add_shimmer()
	pivot_offset = size * 0.5
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	pressed.connect(_on_pressed)
	UITheme.theme_changed.connect(_apply_style)
	resized.connect(_on_resized)


func _apply_style() -> void:
	if accent:
		# No rect StyleBox at all — the chamfered polygon drawn in _draw() is
		# the only visible background. StyleBoxEmpty still gives us the
		# content margins Button needs to lay out its label.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var empty := StyleBoxEmpty.new()
			empty.content_margin_left = 16
			empty.content_margin_right = 16
			empty.content_margin_top = 8
			empty.content_margin_bottom = 8
			add_theme_stylebox_override(state, empty)
	elif solid:
		add_theme_stylebox_override("normal", _make_style(UITheme.button, 0.95))
		add_theme_stylebox_override("hover", _make_style(UITheme.button_hov, 0.95))
		add_theme_stylebox_override("pressed", _make_style(UITheme.button_hov.darkened(0.15), 0.95))
		add_theme_stylebox_override("disabled", _make_style(UITheme.button, 0.4))
	else:
		var base_alpha := 0.18
		add_theme_stylebox_override("normal", _make_style(UITheme.button, base_alpha))
		add_theme_stylebox_override("hover", _make_style(UITheme.button, base_alpha + 0.14))
		add_theme_stylebox_override("pressed", _make_style(UITheme.button, base_alpha + 0.24))
		add_theme_stylebox_override("disabled", _make_style(UITheme.button, 0.08))

	var normal_font: Color = UITheme.accent if accent else (UITheme.dim if dim else UITheme.text)
	add_theme_color_override("font_color", normal_font)
	add_theme_color_override("font_hover_color", UITheme.accent)
	add_theme_color_override("font_pressed_color", UITheme.accent)
	add_theme_color_override("font_disabled_color", UITheme.dim)
	queue_redraw()


func _make_style(base: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(base.r, base.g, base.b, alpha)
	sb.border_color = UITheme.border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _add_shimmer() -> void:
	_shimmer = ColorRect.new()
	_shimmer.color = Color.TRANSPARENT
	_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shimmer_mat = ShaderMaterial.new()
	_shimmer_mat.shader = SHIMMER_SHADER
	_shimmer_mat.set_shader_parameter("intensity", SHIMMER_IDLE)
	_shimmer_mat.set_shader_parameter("speed", SHIMMER_SPEED_IDLE)
	_shimmer.material = _shimmer_mat
	add_child(_shimmer)
	_sync_shimmer_shape()


# Same chamfer math the accent polygon uses (see _draw_accent_shape) — kept
# in one place so the shimmer's clip region can never drift out of sync with
# the drawn shape.
func _chamfer_amount() -> float:
	return clampf(size.y * CHAMFER_FRAC, 4.0, 16.0)


func _sync_shimmer_shape() -> void:
	_shimmer_mat.set_shader_parameter("rect_size", size)
	_shimmer_mat.set_shader_parameter("chamfer_px", _chamfer_amount() if accent else 0.0)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	if _shimmer_mat != null:
		_sync_shimmer_shape()
	queue_redraw()


func _draw() -> void:
	if accent:
		_draw_accent_shape()
	else:
		_draw_bracket_frame()


func _draw_bracket_frame() -> void:
	var hovered := is_hovered()
	var col: Color = UITheme.accent if hovered else UITheme.border
	col.a = 0.35 if disabled else (0.95 if hovered else 0.55)
	var arm: float = minf(size.x, size.y) * BRACKET_LEN_FRAC * (1.3 if hovered else 1.0)
	var width := 2.4 if hovered else 1.5
	var m := BRACKET_MARGIN
	_draw_corner(Vector2(m, m), Vector2(1, 1), arm, col, width)
	_draw_corner(Vector2(size.x - m, m), Vector2(-1, 1), arm, col, width)
	_draw_corner(Vector2(m, size.y - m), Vector2(1, -1), arm, col, width)
	_draw_corner(Vector2(size.x - m, size.y - m), Vector2(-1, -1), arm, col, width)


func _draw_corner(corner: Vector2, dir: Vector2, arm: float, col: Color, width: float) -> void:
	draw_line(corner, corner + Vector2(arm * dir.x, 0), col, width)
	draw_line(corner, corner + Vector2(0, arm * dir.y), col, width)


# Asymmetric hexagon — top-left and bottom-right corners chamfered, the
# other two kept square — filled with a top-lighter/bottom-darker vertical
# gradient (via per-vertex polygon colors, so no shader is needed for the
# fill) and a layered border: a wide dark halo under a thin bright core line.
# Both the fill and the border widen/brighten sharply on hover.
func _draw_accent_shape() -> void:
	var hovered := is_hovered()
	var c := _chamfer_amount()
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(0, h), Vector2(0, c),
	])

	var base: Color = UITheme.accent
	var light := base.lightened(0.3)
	var dark := base.darkened(0.55)
	var fill_alpha := 0.10 if disabled else (0.44 if hovered else 0.16)
	light.a = fill_alpha
	dark.a = fill_alpha
	# Vertices in order: top-left(ish), top-right, right, bottom-right(ish), bottom-left, left.
	var colors := PackedColorArray([light, light, dark, dark, dark, light])
	draw_polygon(pts, colors)

	var loop := pts.duplicate()
	loop.append(pts[0])
	var halo := base.darkened(0.4)
	halo.a = 0.25 if disabled else (0.85 if hovered else 0.4)
	draw_polyline(loop, halo, 6.0 if hovered else 4.0, true)
	var core := base
	core.a = 0.35 if disabled else (1.0 if hovered else 0.65)
	draw_polyline(loop, core, 2.6 if hovered else 1.5, true)


func _on_hover() -> void:
	if disabled:
		return
	AudioManager.ui_hover()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_ANIM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _shimmer_mat != null:
		tw.tween_property(_shimmer_mat, "shader_parameter/intensity", SHIMMER_HOVER, HOVER_ANIM_TIME)
		tw.tween_property(_shimmer_mat, "shader_parameter/speed", SHIMMER_SPEED_HOVER, HOVER_ANIM_TIME)
	queue_redraw()


func _on_unhover() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, HOVER_ANIM_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _shimmer_mat != null:
		tw.tween_property(_shimmer_mat, "shader_parameter/intensity", SHIMMER_IDLE, HOVER_ANIM_TIME + 0.08)
		tw.tween_property(_shimmer_mat, "shader_parameter/speed", SHIMMER_SPEED_IDLE, HOVER_ANIM_TIME + 0.08)
	queue_redraw()


func _on_pressed() -> void:
	if disabled:
		return
	AudioManager.ui_confirm()
