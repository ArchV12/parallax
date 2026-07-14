class_name MiningOperationsPanel
extends Control

# Opened by tapping the MINING row in ActivitiesPanel's gateway list — lists
# every deposit derived at this body (Deposits.deposits_for) as its own
# tappable tile (same whole-row-tappable idiom ActivitiesPanel's own
# AVAILABLE rows use — see _build_deposit_row), since mining is a deliberate
# per-material choice, not an "extract everything" action. Tapping a tile
# opens the owned DepositDetailPanel for that specific material to confirm/
# BEGIN EXTRACTION. Same popup shell as ActivityDetailPanel (UIPanel +
# centered).

signal begin_requested(body_id: String, material_name: String)

const PANEL_WIDTH := 340.0

var _panel: UIPanel
var _list_box: VBoxContainer
var _detail_panel: DepositDetailPanel
var _body_id: String = ""
var _ship_busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)
	vbox.add_child(UIPanel.build_title_header("Mining"))

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_list_box)

	var cancel := UIButton.new()
	cancel.text = "Cancel"
	cancel.dim = true
	cancel.custom_minimum_size = Vector2(0, 30)
	cancel.pressed.connect(_panel.close_animated)
	vbox.add_child(cancel)

	_detail_panel = DepositDetailPanel.new()
	_detail_panel.begin_requested.connect(_on_begin_requested)
	add_child(_detail_panel)


func open_for(body_id: String, ship_busy: bool) -> void:
	_body_id = body_id
	_ship_busy = ship_busy

	for child in _list_box.get_children():
		child.queue_free()

	var deposits := Deposits.deposits_for(body_id)
	if deposits.is_empty():
		var lbl := Label.new()
		lbl.text = "No deposits identified here."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", UITheme.dim)
		_list_box.add_child(lbl)
	else:
		for deposit: DepositInfo in deposits:
			_list_box.add_child(_build_deposit_row(deposit))

	_panel.open_animated()


# Whole-tile tap target — same wrapper/btn/content_margin idiom
# ActivitiesPanel._build_available_row uses (see that function's own comment
# for why: a plain Button behind IGNORE-filtered content, so the label text
# doesn't have to duplicate the button's own styling). Deposit Size/Remaining
# shown right on the tile — the whole reason this is a list of tiles rather
# than one "MINE" button is so the player can compare deposits before
# picking one; the deeper stats (total/rate/difficulty/energy) are one tap
# further in, on DepositDetailPanel.
func _build_deposit_row(deposit: DepositInfo) -> Control:
	var wrapper := MarginContainer.new()

	var btn := Button.new()
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)
	btn.pressed.connect(func() -> void:
		AudioManager.ui_confirm()  # a raw Button, not UIButton — has to do this itself
		_panel.close_animated()  # this panel's own list — DepositDetailPanel is a separate popup layered on top, not nested inside it, so it has to close itself explicitly or it just sits there behind/through the detail panel
		_detail_panel.open_for(_body_id, deposit.material_name, _ship_busy))
	wrapper.add_child(btn)

	var content_margin := MarginContainer.new()
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	wrapper.add_child(content_margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(box)

	var name_label := Label.new()
	name_label.text = deposit.material_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.text)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = "Deposit Size: %s    Remaining: %d%%" % [deposit.deposit_size, roundi(deposit.remaining_fraction * 100.0)]
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 10)
	stats_label.add_theme_color_override("font_color", UITheme.dim)
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats_label)

	return wrapper


func _on_begin_requested(body_id: String, material_name: String) -> void:
	_panel.close_animated()
	begin_requested.emit(body_id, material_name)
