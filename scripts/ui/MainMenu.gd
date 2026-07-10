extends Control

const VERSION := "0.1.0"

const COLOR_ERROR := Color(0.80, 0.30, 0.25)

const BUTTON_MIN_SIZE := Vector2(280, 48)
const FONT_SIZE_TITLE := 64
const FONT_SIZE_BTN   := 18
const FONT_SIZE_SMALL := 14

var _status_label:   Label
var _options_panel:  OptionsUI


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	MusicManager.play_menu()
	UITheme.theme_changed.connect(_on_theme_changed)


# The main menu is built once and sits there — switching flavors via Options
# while looking at it needs an explicit rebuild to actually see it.
# Deferred + queue_free(): this signal fires from inside the Options dropdown's
# own item_selected handler, and the Options panel is one of our children —
# freeing it immediately here would free a node mid-signal-emission.
func _on_theme_changed() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	var options_was_open := _options_panel != null and _options_panel.visible
	# The starfield is theme-independent — keep it running instead of tearing
	# it down and re-scattering a brand new sky every time the flavor changes.
	var starfield: Node = null
	for child in get_children():
		if child is Starfield:
			starfield = child
			continue
		child.queue_free()
	_build(starfield)
	if options_was_open:
		_options_panel.open()


func _build(existing_starfield: Node = null) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(UITheme.bg, 1.0)
	add_child(bg)

	if existing_starfield != null and is_instance_valid(existing_starfield):
		move_child(existing_starfield, bg.get_index() + 1)
	else:
		add_child(Starfield.new())

	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical   = Control.GROW_DIRECTION_BOTH
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 12)
	add_child(centre)

	_add_title(centre)
	_add_spacer(centre, 24)

	_add_button(centre, "New Game", _on_new_game, true)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	_status_label.add_theme_color_override("font_color", UITheme.dim)
	_status_label.text = ""
	centre.add_child(_status_label)

	_options_panel = OptionsUI.new()
	add_child(_options_panel)

	# Secondary/utility actions tucked into a small corner cluster
	var icon_row := HBoxContainer.new()
	icon_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	icon_row.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	icon_row.offset_right  = -16
	icon_row.offset_bottom = -16
	icon_row.add_theme_constant_override("separation", 8)
	add_child(icon_row)
	_add_icon_btn(icon_row, "Forge", _on_forge)
	_add_icon_btn(icon_row, "Options", _on_options)
	_add_icon_btn(icon_row, "Quit", _on_quit)

	var ver := Label.new()
	ver.text = "v" + VERSION
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_left   = 8
	ver.offset_bottom = -6
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)


func _add_title(parent: Control) -> void:
	var title := Label.new()
	title.text = "The Parallax Initiative"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UITheme.text)
	parent.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Push the boundary of human knowledge outward."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	subtitle.add_theme_color_override("font_color", UITheme.dim)
	parent.add_child(subtitle)


func _add_button(parent: Control, label: String, callback: Callable, accent: bool = false) -> UIButton:
	var btn := UIButton.new()
	btn.text = label
	btn.accent = accent
	btn.custom_minimum_size = BUTTON_MIN_SIZE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BTN)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _add_icon_btn(parent: Control, label: String, callback: Callable) -> UIButton:
	var btn := UIButton.new()
	btn.text = label
	btn.dim = true
	btn.custom_minimum_size = Vector2(70, 32)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _add_spacer(parent: Control, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


# --- Handlers ---

func _on_new_game() -> void:
	MusicManager.stop()
	get_tree().change_scene_to_file("res://scenes/boot_sequence.tscn")


func _on_forge() -> void:
	get_tree().change_scene_to_file("res://scenes/cosmic_forge.tscn")


func _on_options() -> void:
	_options_panel.open()


func _on_quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _options_panel != null and _options_panel.visible:
			_options_panel.close()
			accept_event()


# --- Helpers ---

func _set_status(message: String, error: bool = false) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color", COLOR_ERROR if error else UITheme.dim
	)
