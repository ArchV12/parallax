class_name SellCargoPanel
extends Control

# Cockpit-only "sell your mining spoils for Credits" panel (2026-07-14 ask)
# — built as a child of Cockpit's own scene (see Cockpit._build_activities_
# panel), the same "only exists while this scene does" shape ActivitiesPanel/
# SurveyReportPanel already use, rather than living in HUD's persistent
# layer the way CargoPanel does. There's no button anywhere that opens this
# yet, only the Q hotkey (Cockpit._unhandled_input, toggle()) — it needs to
# be structurally impossible to reach from System/Planetary view, not just
# conventionally restricted, which living inside Cockpit's own scene
# guarantees for free (the node doesn't exist at all outside it).
#
# Same full-rect backdrop+centered UIPanel shell as CargoPanel. Each cargo
# row is clickable — clicking one expands an inline slider (0..amount) plus
# a live "Selling: N — +N CR" readout and a SELL button; clicking the same
# row again (or a different row) collapses it. Only one row expanded at a
# time (_expanded_material) — an accordion, not independent per-row state.
# Row state (amount label, slider, etc.) is stashed via set_meta on the
# row's own Control, same idiom ActivitiesPanel's survey cards already use
# for their ProgressBar/op_id, rather than a second parallel lookup Dictionary.
#
# Flat 1 credit/unit for every material today (Economy.CREDITS_PER_UNIT) —
# real per-material pricing is a known, deliberate follow-up ("we'll sort
# out prices later"), not an oversight.

const PANEL_WIDTH := 380.0
const LIST_HEIGHT := 420.0
# Godot's default ScrollContainer scrollbar overlays content instead of
# reserving space for it — this much right margin on the scrolled content
# keeps the scrollbar thumb clear of the right-aligned amount labels.
const SCROLLBAR_GUTTER := 16
# ScrollContainer clips its content rect, and UIButton's hover scale-pop
# (~7%, UIButton.HOVER_SCALE) grows outward from the button's own center —
# the SELL button sitting flush against the scroll area's left/top/bottom
# edges (only the right edge had a margin, reserved for the scrollbar
# gutter above) got its hover state visibly cut off, and the missing left
# margin also read as the button/row not being centered in the panel (16px
# reserved on the right, 0 on the left). Same fix ArrivalScanRow already
# uses for this exact bug — see parallax-godot-technical-lessons memory.
const HOVER_MARGIN := 10

var _panel: UIPanel
var _cards_box: VBoxContainer
var _expanded_material: String = ""  # "" = nothing expanded


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
	outer_vbox.add_child(UIPanel.build_title_header("Sell Cargo"))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", SCROLLBAR_GUTTER)
	scroll_margin.add_theme_constant_override("margin_left", HOVER_MARGIN)
	scroll_margin.add_theme_constant_override("margin_top", HOVER_MARGIN)
	scroll_margin.add_theme_constant_override("margin_bottom", HOVER_MARGIN)
	scroll.add_child(scroll_margin)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_cards_box)

	_add_close_button(outer_vbox)


# Cockpit._unhandled_input's Q handler AND CommandMenu's SELL chip both
# route through this one function — gating Transfer Station access here
# (2026-07-19) covers both entry points with a single check rather than
# duplicating it. Same "click no-ops, plays an error sfx" precedent
# CommandMenu's own Cockpit-context gate already uses for a denied press.
func toggle() -> void:
	if visible:
		close()
	elif Buildings.has_transfer_station(PlayerState.location_id):
		open()
	else:
		AudioManager.ui_deny()


func open() -> void:
	_rebuild()
	visible = true
	_panel.open_animated()


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


# Mining ticks continuously (Operations._tick_mining) while this could
# plausibly be open at the same time — same reasoning as CargoPanel's own
# _process. Only rebuilds on an actual material COUNT change (one fully
# sold off, or a brand new one appearing); otherwise updates each row's
# amount/slider bounds in place so an expanded row doesn't collapse under
# the player mid-drag.
func _process(_delta: float) -> void:
	if not visible:
		return
	var inventory := Deposits.inventory()
	if inventory.size() != _cards_box.get_child_count():
		_rebuild()
		return
	for row in _cards_box.get_children():
		if not row.has_meta("material_name"):
			continue  # the "Cargo hold is empty" placeholder label — nothing to update
		var material_name: String = row.get_meta("material_name")
		var amount: int = inventory.get(material_name, 0)
		(row.get_meta("amount_label") as Label).text = Deposits.format_units(amount)
		if not row.get_meta("expanded"):
			continue
		var slider: HSlider = row.get_meta("slider")
		slider.max_value = maxi(amount, 1)
		if slider.value > amount:
			slider.value = amount
		_update_sell_preview(row)


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
	names.sort()  # alphabetical — same stable order CargoPanel's own list uses
	for material_name: String in names:
		var row := _build_row(material_name, inventory[material_name])
		_cards_box.add_child(row)
		if material_name == _expanded_material:
			_set_expanded(row, true)


func _build_row(material_name: String, amount: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_meta("material_name", material_name)
	box.set_meta("expanded", false)

	# The clickable header — a plain Control rather than a UIButton, since
	# this needs to toggle an accordion state, not fire a single action; the
	# whole row (name + amount) is the click target.
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_row_gui_input.bind(box))
	box.add_child(header)

	var name_label := Label.new()
	name_label.text = material_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var amount_label := Label.new()
	amount_label.text = Deposits.format_units(amount)
	amount_label.add_theme_font_size_override("font_size", 14)
	amount_label.add_theme_color_override("font_color", UITheme.accent)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(amount_label)
	box.set_meta("amount_label", amount_label)

	var expand_box := VBoxContainer.new()
	expand_box.add_theme_constant_override("separation", 6)
	expand_box.visible = false
	box.add_child(expand_box)
	box.set_meta("expand_box", expand_box)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maxi(amount, 1)
	slider.step = 1
	slider.value = amount  # defaults to "sell everything" — the common case is one click away (expand row, SELL) rather than needing to drag up from 0 first
	expand_box.add_child(slider)
	box.set_meta("slider", slider)

	var preview_label := Label.new()
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 12)
	preview_label.add_theme_color_override("font_color", UITheme.dim)
	expand_box.add_child(preview_label)
	box.set_meta("preview_label", preview_label)

	var sell_btn := UIButton.new()
	sell_btn.text = "SELL"
	sell_btn.solid = true
	sell_btn.shimmer_enabled = false
	sell_btn.press_sfx = "sell_button"  # override — a distinct cash-register-style cue instead of the generic button click, see AudioManager.ui_confirm
	sell_btn.custom_minimum_size = Vector2(0, 30)
	expand_box.add_child(sell_btn)
	box.set_meta("sell_btn", sell_btn)
	sell_btn.pressed.connect(_on_sell_pressed.bind(box))

	slider.value_changed.connect(func(_v: float) -> void: _update_sell_preview(box))
	_update_sell_preview(box)

	return box


func _on_row_gui_input(event: InputEvent, row: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		AudioManager.ui_confirm("button_general")
		_toggle_row(row)


# Accordion — collapses whatever was previously expanded (there's at most
# one) before expanding the newly-clicked row, or collapses everything if
# the already-expanded row was clicked again.
func _toggle_row(row: Control) -> void:
	var material_name: String = row.get_meta("material_name")
	var now_expanding := _expanded_material != material_name
	for child in _cards_box.get_children():
		if child.has_meta("expanded"):
			_set_expanded(child, false)
	_expanded_material = material_name if now_expanding else ""
	if now_expanding:
		_set_expanded(row, true)


func _set_expanded(row: Control, expanded: bool) -> void:
	row.set_meta("expanded", expanded)
	(row.get_meta("expand_box") as Control).visible = expanded


func _update_sell_preview(row: Control) -> void:
	var slider: HSlider = row.get_meta("slider")
	var preview_label: Label = row.get_meta("preview_label")
	var sell_btn: UIButton = row.get_meta("sell_btn") if row.has_meta("sell_btn") else null
	var qty := int(slider.value)
	var credits := qty * Economy.CREDITS_PER_UNIT
	preview_label.text = "Selling %s — +%s CR" % [Deposits.format_units(qty), Deposits.format_units(credits)]
	if sell_btn != null:
		sell_btn.disabled = qty <= 0


func _on_sell_pressed(row: Control) -> void:
	var material_name: String = row.get_meta("material_name")
	var slider: HSlider = row.get_meta("slider")
	var qty := int(slider.value)
	if qty <= 0:
		return
	if not Deposits.spend_materials({material_name: qty}):
		return  # defensive only — the slider is already clamped to the live amount
	Economy.add_credits(qty * Economy.CREDITS_PER_UNIT)
	_rebuild()
