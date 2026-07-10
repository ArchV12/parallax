class_name PauseMenu
extends Control

# The in-game System panel — reached via the console's SYSTEM button, or Esc
# in Cockpit (see the parallax-core-design-decisions memory: this replaces
# Cockpit's old instant hard-exit-to-menu). Resume/Options/Save/Quit;
# Options reuses the exact panel the main menu uses (in_game = true hides
# the theme dropdown there, an existing OptionsUI convention for persistent
# in-session panels — see OptionsUI.gd). Save has no backing system yet, so
# it's left active/clickable rather than disabled, same as this session's
# other not-yet-built console buttons — it just has nothing connected to
# `pressed`, so a click no-ops.

var _panel: UIPanel
var _options: OptionsUI


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
	_panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SYSTEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_add_action(vbox, "Resume", close)
	_add_action(vbox, "Options", _on_options)
	_add_action(vbox, "Save")
	vbox.add_child(HSeparator.new())
	_add_action(vbox, "Quit to Main Menu", _on_quit)

	_options = OptionsUI.new()
	_options.in_game = true
	add_child(_options)


func open() -> void:
	visible = true
	_panel.open_animated()


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


# Skips the close animation — used when leaving gameplay entirely (see
# HUD.hide_hud()), where there's no time to wait out a tween mid-transition.
func force_close() -> void:
	visible = false
	_options.visible = false


func _add_action(parent: VBoxContainer, label: String, callback: Callable = Callable()) -> void:
	var btn := UIButton.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 14)
	if callback.is_valid():
		btn.pressed.connect(callback)
	parent.add_child(btn)


func _on_options() -> void:
	_options.open()


func _on_quit() -> void:
	HUD.hide_hud()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
