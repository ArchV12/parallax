class_name OptionsUI
extends Control

const PREFS_PATH := "user://prefs.json"

var _music_slider:   HSlider
var _sfx_slider:     HSlider
var _ambient_slider: HSlider
var _theme_option:   OptionButton
var _panel:          UIPanel

# Set true for an in-game pause Options panel. Persistent in-game panels are
# built once at session start and never pick up a live flavor switch, so the
# theme dropdown is disabled in-game and only enabled at the MainMenu.
var in_game: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	_load_and_apply()


func open() -> void:
	visible = true
	_panel.open_animated()


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var audio_title := Label.new()
	audio_title.text = "AUDIO"
	audio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_title.add_theme_font_size_override("font_size", 13)
	audio_title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(audio_title)

	_music_slider   = _add_slider_row(vbox, "Music")
	_sfx_slider     = _add_slider_row(vbox, "SFX")
	_ambient_slider = _add_slider_row(vbox, "Ambient")

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_ambient_slider.value_changed.connect(_on_ambient_changed)

	vbox.add_child(HSeparator.new())

	var appearance_title := Label.new()
	appearance_title.text = "APPEARANCE"
	appearance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	appearance_title.add_theme_font_size_override("font_size", 13)
	appearance_title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(appearance_title)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 8)
	vbox.add_child(theme_row)

	var theme_lbl := Label.new()
	theme_lbl.text = "UI Color"
	theme_lbl.add_theme_font_size_override("font_size", 13)
	theme_lbl.add_theme_color_override("font_color", UITheme.text)
	theme_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_lbl)

	_theme_option = OptionButton.new()
	for flavor_name: String in UITheme.flavor_names():
		_theme_option.add_item(flavor_name)
	_theme_option.selected = UITheme.flavor
	_theme_option.item_selected.connect(_on_theme_selected)
	if in_game:
		_theme_option.disabled = true
		_theme_option.tooltip_text = "Change UI color from the Main Menu"
	theme_row.add_child(_theme_option)

	if in_game:
		var theme_hint := Label.new()
		theme_hint.text = "(change from Main Menu)"
		theme_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		theme_hint.add_theme_font_size_override("font_size", 11)
		theme_hint.add_theme_color_override("font_color", UITheme.dim)
		vbox.add_child(theme_hint)

	vbox.add_child(HSeparator.new())

	var close_btn := UIButton.new()
	close_btn.text = "Back"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


func _add_slider_row(parent: VBoxContainer, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(52, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UITheme.text)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var pct := Label.new()
	pct.text = "100%"
	pct.custom_minimum_size = Vector2(40, 0)
	pct.add_theme_font_size_override("font_size", 13)
	pct.add_theme_color_override("font_color", UITheme.dim)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)

	slider.set_meta("pct_label", pct)
	return slider


func _on_music_changed(value: float) -> void:
	_apply_bus("Music", value)
	_update_pct(_music_slider)
	_save()


func _on_sfx_changed(value: float) -> void:
	_apply_bus("SFX", value)
	_update_pct(_sfx_slider)
	_save()


func _on_ambient_changed(value: float) -> void:
	_apply_bus("Ambient", value)
	_update_pct(_ambient_slider)
	_save()


# UITheme.set_flavor() notifies listeners immediately, but this panel's own
# styleboxes were already baked with the old flavor's colors — rebuild it too
# so picking a flavor previews it right here. Deferred because we're still
# inside the OptionButton's own item_selected emission; freeing it now would
# free a node mid-signal.
func _on_theme_selected(idx: int) -> void:
	UITheme.set_flavor(idx as UITheme.Flavor)
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_build()
	_load_and_apply()


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _update_pct(slider: HSlider) -> void:
	var lbl: Label = slider.get_meta("pct_label")
	lbl.text = "%d%%" % int(slider.value * 100.0)


func _load_and_apply() -> void:
	var prefs := _read_prefs()
	var music_vol:   float = prefs.get("music_volume",   0.2)
	var sfx_vol:     float = prefs.get("sfx_volume",     1.0)
	var ambient_vol: float = prefs.get("ambient_volume", 0.2)
	_music_slider.set_value_no_signal(music_vol)
	_sfx_slider.set_value_no_signal(sfx_vol)
	_ambient_slider.set_value_no_signal(ambient_vol)
	_apply_bus("Music",   music_vol)
	_apply_bus("SFX",     sfx_vol)
	_apply_bus("Ambient", ambient_vol)
	_update_pct(_music_slider)
	_update_pct(_sfx_slider)
	_update_pct(_ambient_slider)


func _save() -> void:
	var prefs := _read_prefs()
	prefs["music_volume"]   = _music_slider.value
	prefs["sfx_volume"]     = _sfx_slider.value
	prefs["ambient_volume"] = _ambient_slider.value
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(prefs))


func _read_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
