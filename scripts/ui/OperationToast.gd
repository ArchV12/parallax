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

# Sits directly under HUD's KnowledgeBar (top-center, offset_top 20, roughly
# 30px tall at its current font sizes — a 10pt name row over a 14pt value
# row) — this clears its bottom edge with a comfortable visible gap.
# Positioned by measuring our own panel's width every time the text changes
# (see _recenter_horizontally) rather than relying on an anchor-only
# auto-center, since a plain (non-Container) Control doesn't pick up its
# child's minimum size for that automatically — same reasoning HUD's own
# _layout_knowledge_bar measures-then-centers instead of trusting anchors.
const TOP_OFFSET := 68.0

var _panel: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_top = TOP_OFFSET
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.panel.r, UITheme.panel.g, UITheme.panel.b, 0.92)
	style.border_color = UITheme.accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", UITheme.text)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

	_recenter_horizontally()


func show_toast(text: String) -> void:
	_label.text = text
	_recenter_horizontally()
	if _tween != null and _tween.is_valid():
		_tween.kill()

	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_interval(DISPLAY_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)


# Re-measures the panel (its width changes with every message) and
# re-centers it horizontally — called on build and on every new toast.
func _recenter_horizontally() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	offset_left = (viewport_width - _panel.get_minimum_size().x) * 0.5
