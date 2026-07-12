class_name CheatMenu
extends Control

# Dev-only engine tier picker — F2 toggles this (see HUD._unhandled_input),
# replacing the old single on/off "cheat engine" boost. Lets a tester pin
# PlayerState.engine_tier_override to any of TravelCalc.ENGINE_TIERS (or
# back off, "Normal") to preview the real-time-scale model — see the
# travel-time-scale brainstorm in parallax-core-design-decisions memory —
# without needing to actually reach that tier through progression, which
# doesn't exist yet.
#
# Same overlay shape as PauseMenu (backdrop + centered UIPanel), but no
# open/close animation — this is a snap-open dev tool, not a gameplay beat
# worth a flourish.

const NORMAL_LABEL := "Normal (Gameplay Pacing)"

var _panel: UIPanel
var _status_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "ENGINE CHEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(_status_label)

	vbox.add_child(HSeparator.new())

	_add_tier_button(vbox, -1, NORMAL_LABEL)
	for i in TravelCalc.ENGINE_TIERS.size():
		var tier: Dictionary = TravelCalc.ENGINE_TIERS[i]
		_add_tier_button(vbox, i, tier["name"])

	vbox.add_child(HSeparator.new())
	_add_close_button(vbox)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_status()


func _add_tier_button(parent: VBoxContainer, tier: int, label: String) -> void:
	var btn := UIButton.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void:
		PlayerState.set_engine_tier(tier)
		_refresh_status())
	parent.add_child(btn)


func _add_close_button(parent: VBoxContainer) -> void:
	var btn := UIButton.new()
	btn.text = "Close"
	btn.dim = true
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void: visible = false)
	parent.add_child(btn)


func _refresh_status() -> void:
	if PlayerState.engine_tier_override < 0:
		_status_label.text = "ACTIVE: %s" % NORMAL_LABEL
		return
	var tier: Dictionary = TravelCalc.ENGINE_TIERS[PlayerState.engine_tier_override]
	_status_label.text = "ACTIVE: %s" % tier["name"]
