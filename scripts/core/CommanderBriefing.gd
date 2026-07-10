extends Control

# The player's first view after starting a new game — a mission briefing
# card introducing the commander, vessel, and starting situation, over the
# same deep-space starfield backdrop as the main menu. Replaces the bare
# game_placeholder.tscn as the "New Game" destination directly; "Begin
# Mission" carries on to that placeholder until a real cockpit view exists.

const PANEL_DELAY := 0.3
const TYPE_CHARS_PER_SEC := 35.0
const TYPE_MIN_TIME := 0.06
const TYPE_CLICK_STRIDE := 3  # click every Nth typed char — several short fields in a row, so lighter than Boot Sequence's stride

var _panel: UIPanel
var _type_labels: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HUD.hide_hud()

	# True space-black, not the theme's bg color — see the same fix in
	# MainMenu.gd.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	add_child(bg)

	add_child(Starfield.new())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.visible = false
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	vbox.add_child(UIPanel.build_title_header("Commander Profile"))
	_add_spacer(vbox, 10)

	_add_field(vbox, "Vessel", "Horizon Explorer")
	_add_spacer(vbox, 10)
	_add_field(vbox, "Location", "Earth Orbit")
	_add_spacer(vbox, 10)
	_add_field(vbox, "Mission", "Humanity's First Independent Expedition")
	_add_spacer(vbox, 14)

	var dest_lbl := Label.new()
	dest_lbl.text = "AVAILABLE DESTINATIONS"
	dest_lbl.add_theme_font_size_override("font_size", 12)
	dest_lbl.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(dest_lbl)
	_add_spacer(vbox, 6)

	for dest: String in ["Moon", "Low Earth Orbit", "Near Earth Asteroids"]:
		_add_destination(vbox, dest)

	_add_spacer(vbox, 18)

	var begin_btn := UIButton.new()
	begin_btn.text = "Begin Mission"
	begin_btn.accent = true
	begin_btn.custom_minimum_size = Vector2(0, 44)
	begin_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	begin_btn.add_theme_font_size_override("font_size", 16)
	begin_btn.pressed.connect(_on_begin)
	vbox.add_child(begin_btn)

	_add_spacer(vbox, 4)

	var hint := Label.new()
	hint.text = "Esc — return to menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(hint)

	var panel_tw := create_tween()
	panel_tw.tween_interval(PANEL_DELAY)
	panel_tw.tween_callback(_panel.open_animated)
	panel_tw.tween_interval(UIPanel.ANIM_TIME + 0.05)
	panel_tw.tween_callback(_start_typing)


# Types out the data lines (field values, destinations) in sequence — quick,
# terminal-style. Labels/headers around them are chrome, not data, so they
# just appear immediately with the panel rather than typing too.
func _start_typing() -> void:
	_type_sequence()


func _type_sequence() -> void:
	for lbl in _type_labels:
		await _type_label(lbl)


# Steps one character at a time rather than a single tween, so a click sfx
# can fire in lockstep with each character — same total duration as before,
# just with clicks along the way.
func _type_label(lbl: Label) -> void:
	var total_len := lbl.text.length()
	if total_len == 0:
		return
	var dur := maxf(total_len / TYPE_CHARS_PER_SEC, TYPE_MIN_TIME)
	var char_time := dur / total_len
	var clickable_count := 0
	for i in range(total_len):
		lbl.visible_ratio = float(i + 1) / float(total_len)
		var ch := lbl.text[i]
		if ch != " " and ch != "\n":
			clickable_count += 1
			if clickable_count % TYPE_CLICK_STRIDE == 1:
				AudioManager.type_char()
		await get_tree().create_timer(char_time).timeout


func _register_typed(lbl: Label) -> void:
	lbl.visible_ratio = 0.0
	_type_labels.append(lbl)


func _add_spacer(parent: Control, h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


func _add_field(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var lbl := Label.new()
	lbl.text = label_text.to_upper()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.accent)
	parent.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", UITheme.text)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(val)
	_register_typed(val)


func _add_destination(parent: VBoxContainer, dest_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var bullet := Label.new()
	bullet.text = "◉"
	bullet.add_theme_font_size_override("font_size", 13)
	bullet.add_theme_color_override("font_color", UITheme.accent)
	row.add_child(bullet)

	var lbl := Label.new()
	lbl.text = dest_name
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", UITheme.text)
	row.add_child(lbl)
	_register_typed(lbl)

	_add_spacer(parent, 4)


func _on_begin() -> void:
	get_tree().change_scene_to_file("res://scenes/cockpit.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
