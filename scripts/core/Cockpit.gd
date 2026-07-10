extends Control

# The player's real "game" view, reached straight from the boot sequence for
# now — CommanderBriefing is kept around but temporarily pulled out of the
# New Game flow (see BootSequence._finish / CommanderBriefing._on_begin).
# Starts bare: a starfield backdrop and two HUD corner readouts. Grows from
# here as the actual command-vessel interface comes together.
#
# Music is hardcoded to Earth Orbit for now since there's no location system
# yet — the game always starts there. Once travel/location tracking exists,
# this should switch to whatever MusicManager.play_<location>() the player's
# current position calls for instead of always playing Earth Orbit.

var _system_label: Label
var _year_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	add_child(Starfield.new())

	_system_label = _make_hud_label(Control.PRESET_TOP_LEFT)
	_system_label.offset_left = 24
	_system_label.offset_top = 20
	_system_label.text = "TPI COMMAND SYSTEM"

	_year_label = _make_hud_label(Control.PRESET_TOP_RIGHT)
	_year_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_year_label.offset_right = -24
	_year_label.offset_top = 20
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_year_label.text = "YEAR 2037"

	UITheme.theme_changed.connect(_on_theme_changed)

	MusicManager.play_earth_orbit()


func _make_hud_label(preset: Control.LayoutPreset) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.text)
	add_child(l)
	return l


func _on_theme_changed() -> void:
	_system_label.add_theme_color_override("font_color", UITheme.text)
	_year_label.add_theme_color_override("font_color", UITheme.text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
