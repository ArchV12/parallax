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
var _science_status_label: Label
var _economy_status_label: Label


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
	_build_science_cheat(vbox)

	vbox.add_child(HSeparator.new())
	_build_economy_cheat(vbox)

	vbox.add_child(HSeparator.new())
	_add_close_button(vbox)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_status()
		_refresh_science_status()
		_refresh_economy_status()


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


# Manual survey clicks only award 10 Knowledge each (Research.
# SURVEY_KNOWLEDGE_AWARD) — reaching the later resource_survey thresholds
# (up to 1000) would take dozens of clicks, so this fast-forwards Knowledge
# directly for testing Phase 3's milestone/instrument-grant pipeline without
# needing a real save/load or a hundred button presses.
func _build_science_cheat(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "SCIENCE CHEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	parent.add_child(title)

	_science_status_label = Label.new()
	_science_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_science_status_label.add_theme_font_size_override("font_size", 12)
	_science_status_label.add_theme_color_override("font_color", UITheme.dim)
	parent.add_child(_science_status_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	_add_knowledge_button(row, 50)
	_add_knowledge_button(row, 200)

	_refresh_science_status()


func _add_knowledge_button(parent: HBoxContainer, amount: int) -> void:
	var btn := UIButton.new()
	btn.text = "+%d Resource" % amount
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void:
		Research.add_knowledge("resource", amount)
		_refresh_science_status())
	parent.add_child(btn)


func _refresh_science_status() -> void:
	var instrument := Research.current_instrument("resource_survey")
	_science_status_label.text = "Resource Knowledge: %d — %s" % [
		Research.knowledge("resource"), instrument.display_name if instrument != null else "—"
	]


# Fast-forwards Credits for testing anything gated behind Economy.balance
# (Buildings construction costs, SellCargoPanel-adjacent flows) without
# needing to actually mine/sell a real amount first.
func _build_economy_cheat(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "ECONOMY CHEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	parent.add_child(title)

	_economy_status_label = Label.new()
	_economy_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_economy_status_label.add_theme_font_size_override("font_size", 12)
	_economy_status_label.add_theme_color_override("font_color", UITheme.dim)
	parent.add_child(_economy_status_label)

	var btn := UIButton.new()
	btn.text = "+10,000 Credits"
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void:
		Economy.add_credits(10000)
		_refresh_economy_status())
	parent.add_child(btn)

	_refresh_economy_status()


func _refresh_economy_status() -> void:
	_economy_status_label.text = "Credits: %s" % Deposits.format_units(Economy.balance)
