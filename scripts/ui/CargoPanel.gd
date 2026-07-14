class_name CargoPanel
extends Control

# The in-game Cargo hold — reached via the console's CARGO button. Purely
# passive: surfaces exactly what Deposits.gd already tracks (materials
# mined so far, ship-wide — not broken down by which body they came from,
# nothing currently needs that distinction) — no new mechanics. Same
# full-rect backdrop+centered UIPanel shape as ResearchPanel/PauseMenu/
# CheatMenu.

const PANEL_WIDTH := 380.0
const LIST_HEIGHT := 420.0
# Godot's default ScrollContainer scrollbar overlays content instead of
# reserving space for it — this much right margin on the scrolled content
# keeps the scrollbar thumb clear of the right-aligned amount labels.
const SCROLLBAR_GUTTER := 16

var _panel: UIPanel
var _cards_box: VBoxContainer
var _amount_labels: Dictionary = {}  # material_name -> Label, kept live so _process can update values in place without a full rebuild every frame (which would also reset scroll position)


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
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(outer_vbox)
	outer_vbox.add_child(UIPanel.build_title_header("Cargo"))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", SCROLLBAR_GUTTER)
	scroll.add_child(scroll_margin)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_cards_box)

	_add_close_button(outer_vbox)


func open() -> void:
	_rebuild()
	visible = true
	_panel.open_animated()


# Mining ticks continuously (Operations._tick_mining) — a snapshot taken
# once at open() would sit there reading a stale number for however long
# the player leaves the panel open. Cheap to just re-read Deposits every
# frame while visible: only updates existing labels' text in place unless
# the material COUNT changed (a genuinely new material appearing for the
# first time), which is the one case a full _rebuild is actually needed for.
func _process(_delta: float) -> void:
	if not visible:
		return
	var inventory := Deposits.inventory()
	if inventory.size() != _amount_labels.size():
		_rebuild()
		return
	for material_name: String in inventory:
		var label: Label = _amount_labels.get(material_name)
		if label != null:
			label.text = Deposits.format_units(inventory[material_name])


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


# Skips the close animation — used when leaving gameplay entirely, same as
# PauseMenu.force_close/ResearchPanel.force_close.
func force_close() -> void:
	visible = false


func _add_close_button(parent: VBoxContainer) -> void:
	var btn := UIButton.new()
	btn.text = "Close"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(close)
	parent.add_child(btn)


func _rebuild() -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_amount_labels.clear()

	var inventory := Deposits.inventory()
	if inventory.is_empty():
		var lbl := Label.new()
		lbl.text = "Cargo hold is empty."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", UITheme.dim)
		_cards_box.add_child(lbl)
		return

	var names := inventory.keys()
	names.sort()  # alphabetical — a stable, predictable order regardless of mining sequence
	for material_name: String in names:
		_cards_box.add_child(_build_row(material_name, inventory[material_name]))


func _build_row(material_name: String, amount: int) -> Control:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = material_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var amount_label := Label.new()
	amount_label.text = Deposits.format_units(amount)
	amount_label.add_theme_font_size_override("font_size", 14)
	amount_label.add_theme_color_override("font_color", UITheme.accent)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount_label)
	_amount_labels[material_name] = amount_label

	return row
