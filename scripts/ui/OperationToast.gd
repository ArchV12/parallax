class_name OperationToast
extends Control

# Lightweight, non-blocking, auto-dismissing banner — deliberately NOT a
# full UIPanel popup (no chamfered shape, no DISMISS button, nothing to
# interact with): this is meant to be glanced at from any view, not read
# like SurveyReportPanel/EarthTransmissionBanner. Lives in HUD (see
# HUD._build_hud), the one autoload CanvasLayer guaranteed to exist
# regardless of which scene is currently active — that's the whole point,
# since what triggers this (Operations.operation_completed/
# Research.milestone_reached) can now fire while the player is anywhere.
#
# Single-slot: a second show_toast() call while one is already showing
# restarts it with the new text rather than queuing — matches "only one
# operation can run at a time" for now; a real queue isn't needed yet.

const DISPLAY_SECONDS := 3.5
const FADE_SECONDS := 0.3

var _label: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_top = 64.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.panel.r, UITheme.panel.g, UITheme.panel.b, 0.92)
	style.border_color = UITheme.accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", UITheme.text)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


func show_toast(text: String) -> void:
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()

	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_interval(DISPLAY_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
