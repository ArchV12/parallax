extends Node

# Persistent HUD — an autoload, so unlike everything inside a view's own
# scene tree it survives every change_scene_to_file() swap. Fixed, always-on
# chrome (system status, year, the view-name readout, view-switch nav) lives
# here exactly once instead of being copy-pasted into every view scene; each
# view scene only builds whatever's unique to it.
#
# Metaphor: think of this as the Enterprise's bridge console, not the main
# viewer — it's the instrumentation that's always lit, separate from
# whatever's currently showing on the viewscreen (the swapped 3D scene
# underneath). Switching views is a quick flicker/fade of the viewer, not a
# camera move through space — see the transition decision in the
# parallax-core-design-decisions memory.
#
# Any screen that ISN'T an in-flight view (MainMenu, BootSequence,
# CommanderBriefing, Cosmic Forge, ...) must call hide_hud() in its own
# _ready() — the HUD has no way to know when you've left gameplay other than
# being told, and defaults to hidden so a forgotten call fails safe (no HUD)
# rather than leaking gameplay chrome onto a menu screen.

const TRANSITION_FADE_TIME := 0.18
const TRANSITION_HOLD_TIME := 0.05

var _hud_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _system_label: Label
var _year_label: Label
var _view_label: Label
var _nav_button: UIButton
var _fade_rect: ColorRect

var _nav_target_scene: String = ""


func _ready() -> void:
	# Fade sits between the 3D viewer (layer 0) and the HUD (layer 100) —
	# the console stays lit and readable through the flicker; only the
	# viewer itself blacks out.
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 50
	add_child(_fade_layer)

	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	add_child(_hud_layer)

	_build_fade()
	_build_hud()
	hide_hud()

	UITheme.theme_changed.connect(_on_theme_changed)


func _build_fade() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func _build_hud() -> void:
	_system_label = _make_label(Control.PRESET_TOP_LEFT)
	_system_label.offset_left = 24
	_system_label.offset_top = 20
	_system_label.text = "TPI COMMAND SYSTEM"

	_year_label = _make_label(Control.PRESET_TOP_RIGHT)
	_year_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_year_label.offset_right = -24
	_year_label.offset_top = 20
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_year_label.text = "YEAR 2037"

	_view_label = _make_label(Control.PRESET_TOP_LEFT)
	_view_label.offset_left = 24
	_view_label.offset_top = 46
	_view_label.add_theme_font_size_override("font_size", 12)
	_view_label.add_theme_color_override("font_color", UITheme.dim)

	# Placeholder position — bottom-right for now, will get tucked into the
	# real HUD chrome once that exists.
	_nav_button = UIButton.new()
	_nav_button.custom_minimum_size = Vector2(100, 36)
	_nav_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_nav_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_nav_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_nav_button.offset_right = -16
	_nav_button.offset_bottom = -16
	_nav_button.pressed.connect(_on_nav_pressed)
	_hud_layer.add_child(_nav_button)


func _make_label(preset: Control.LayoutPreset) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.text)
	_hud_layer.add_child(l)
	return l


func _on_theme_changed() -> void:
	_system_label.add_theme_color_override("font_color", UITheme.text)
	_year_label.add_theme_color_override("font_color", UITheme.text)


# --- Visibility ---

func show_hud() -> void:
	_hud_layer.visible = true


func hide_hud() -> void:
	_hud_layer.visible = false


# --- View registration ---
# Every in-flight view scene calls this from its own _ready() to tell the
# HUD what it is — updates the view-name readout and configures the nav
# button to lead to whatever view is next (e.g. Cockpit registers "System"
# leading to system_view.tscn; System view registers "Cockpit" leading back).
func set_view(view_name: String, nav_label: String, nav_target_scene: String) -> void:
	show_hud()
	_view_label.text = view_name.to_upper()
	_nav_button.text = nav_label
	_nav_target_scene = nav_target_scene


func _on_nav_pressed() -> void:
	go_to(_nav_target_scene)


# --- Transition ---
# Quick flicker/fade of the viewer only (the console stays lit throughout,
# per the fade/HUD layer split above) — sells "the main viewer just
# switched feed," not a literal camera move through space.
func go_to(scene_path: String) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, TRANSITION_FADE_TIME)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene_path))
	tw.tween_interval(TRANSITION_HOLD_TIME)
	tw.tween_property(_fade_rect, "modulate:a", 0.0, TRANSITION_FADE_TIME)
