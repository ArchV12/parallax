extends Control

# Stand-in for the real game scene so the menu → game → menu flow exists.
# Replaced by the actual cockpit/system-view scene once it's built.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	add_child(bg)

	add_child(Starfield.new())

	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical   = Control.GROW_DIRECTION_BOTH
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 8)
	add_child(centre)

	var lbl := Label.new()
	lbl.text = "The universe isn't built yet."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", UITheme.text)
	centre.add_child(lbl)

	var hint := Label.new()
	hint.text = "Esc — return to menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.dim)
	centre.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
