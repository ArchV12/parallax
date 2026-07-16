class_name CargoPanel
extends Control

# The in-game Cargo hold — reached via the console's CARGO button. Mostly
# passive: surfaces exactly what Deposits.gd already tracks (materials
# mined so far, ship-wide — not broken down by which body they came from,
# nothing currently needs that distinction) — no new mechanics. Same
# full-rect backdrop+centered UIPanel shape as ResearchPanel/PauseMenu/
# CheatMenu.
#
# A second, narrower UIPanel — Equipment — sits attached to the left of the
# main Cargo panel (2026-07-14 ask), listing the player's current instrument
# per Science activity (Research.current_instrument), the same "what's
# actually equipped right now" data ResearchPanel's own per-activity detail
# already surfaces — just gathered into one glance here instead of digging
# through each activity's own drawer. Read-only, same as the cargo list
# itself; nothing here is interactive.
#
# A capacity readout (2026-07-14 ask, same day) sits in its own strip across
# the bottom of the main Cargo panel, above the Close button — total units
# held across every material vs. Deposits.CARGO_CAPACITY (a flat, hardcoded
# hold size for now — no per-material limits, no upgrade path yet). This is
# purely a display; the actual stop-mining-at-capacity enforcement lives in
# Operations._tick_mining, which is the thing that actually has to decide
# mid-tick whether another unit still fits.

const PANEL_WIDTH := 380.0
const EQUIPMENT_PANEL_WIDTH := 240.0
const PANEL_GAP := 12.0
const LIST_HEIGHT := 420.0
# Godot's default ScrollContainer scrollbar overlays content instead of
# reserving space for it — this much right margin on the scrolled content
# keeps the scrollbar thumb clear of the right-aligned amount labels.
const SCROLLBAR_GUTTER := 16

var _panel: UIPanel
var _equipment_panel: UIPanel
var _equipment_box: VBoxContainer
var _cards_box: VBoxContainer
var _amount_labels: Dictionary = {}  # material_name -> Label, kept live so _process can update values in place without a full rebuild every frame (which would also reset scroll position)
var _capacity_value: Label
var _capacity_bar: ProgressBar


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

	# Equipment (left) and Cargo (right) are two SEPARATE UIPanels side by
	# side in one HBoxContainer, not one wider panel with two sections —
	# each keeps its own chamfered-hexagon border/glow, which is what
	# actually reads as "attached" rather than "merged into one shape."
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PANEL_GAP)
	center.add_child(row)

	_equipment_panel = UIPanel.new()
	_equipment_panel.custom_minimum_size = Vector2(EQUIPMENT_PANEL_WIDTH, 0)
	row.add_child(_equipment_panel)

	var equipment_vbox := VBoxContainer.new()
	equipment_vbox.add_theme_constant_override("separation", 12)
	_equipment_panel.add_child(equipment_vbox)
	equipment_vbox.add_child(UIPanel.build_title_header("Equipment"))

	_equipment_box = VBoxContainer.new()
	_equipment_box.add_theme_constant_override("separation", 10)
	equipment_vbox.add_child(_equipment_box)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	row.add_child(_panel)

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

	outer_vbox.add_child(HSeparator.new())
	outer_vbox.add_child(_build_capacity_section())

	_add_close_button(outer_vbox)


func open() -> void:
	_rebuild()
	_rebuild_equipment()
	_update_capacity()
	visible = true
	_panel.open_animated()
	_equipment_panel.open_animated()


# Mining ticks continuously (Operations._tick_mining) — a snapshot taken
# once at open() would sit there reading a stale number for however long
# the player leaves the panel open. Cheap to just re-read Deposits every
# frame while visible: only updates existing labels' text in place unless
# the material COUNT changed (a genuinely new material appearing for the
# first time), which is the one case a full _rebuild is actually needed for.
func _process(_delta: float) -> void:
	if not visible:
		return
	_update_capacity()
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
	_equipment_panel.close_animated()
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


# Built once on open(), not re-polled every frame like _cards_box — an
# instrument tier only ever changes via a milestone (Research.
# milestone_reached), never mid-glance at this panel, so there's nothing to
# keep live here the way mining totals need. Research.known_activities()
# iterates _activities in ACTIVITY_PATHS' own declared order (resource_
# survey, geological_survey, mining) — a fixed, sensible display order,
# nothing to sort.
func _rebuild_equipment() -> void:
	for child in _equipment_box.get_children():
		child.queue_free()

	for activity_id: String in Research.known_activities():
		var def := Research.activity_def(activity_id)
		var activity_name := def.display_name if def != null else activity_id
		var instrument := Research.current_instrument(activity_id)
		# LOCKED shouldn't actually be reachable today (every known activity
		# is granted a starting tier from the moment a game begins — see
		# Research.STARTING_ACTIVITIES) — kept only so this doesn't silently
		# mislabel a future activity that ISN'T auto-granted the same way.
		var instrument_name := instrument.display_name if instrument != null else "LOCKED"
		_equipment_box.add_child(_build_equipment_row(activity_name, instrument_name))


func _build_equipment_row(activity_name: String, instrument_name: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var activity_label := Label.new()
	activity_label.text = activity_name.to_upper()
	activity_label.add_theme_font_size_override("font_size", 11)
	activity_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(activity_label)

	var instrument_label := Label.new()
	instrument_label.text = instrument_name
	instrument_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	instrument_label.add_theme_font_size_override("font_size", 14)
	instrument_label.add_theme_color_override("font_color", UITheme.text)
	box.add_child(instrument_label)

	return box


func _build_capacity_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	box.add_child(row)

	var label := Label.new()
	label.text = "CARGO CAPACITY"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.dim)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	_capacity_value = Label.new()
	_capacity_value.add_theme_font_size_override("font_size", 13)
	_capacity_value.add_theme_color_override("font_color", UITheme.text)
	_capacity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_capacity_value)

	# Same shape as ActivitiesPanel's own survey progress bars (see that
	# file's _make_bar_style) — not shared code, just the same small pattern
	# repeated locally; not worth extracting for two call sites this simple.
	_capacity_bar = ProgressBar.new()
	_capacity_bar.custom_minimum_size = Vector2(0, 8)
	_capacity_bar.show_percentage = false
	_capacity_bar.min_value = 0.0
	_capacity_bar.max_value = 1.0
	_capacity_bar.add_theme_stylebox_override("fill", _make_bar_style(UITheme.accent, 1.0))
	_capacity_bar.add_theme_stylebox_override("background", _make_bar_style(UITheme.border, 0.3))
	box.add_child(_capacity_bar)

	return box


func _make_bar_style(col: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := col
	c.a = alpha
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


func _update_capacity() -> void:
	var used := Deposits.total_cargo_used()
	_capacity_value.text = "%s / %s" % [Deposits.format_units(used), Deposits.format_units(Deposits.CARGO_CAPACITY)]
	_capacity_bar.value = float(used) / float(Deposits.CARGO_CAPACITY)
