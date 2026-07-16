class_name DepositDetailPanel
extends Control

# Centered confirm panel opened by tapping a deposit tile in
# MiningOperationsPanel's list — Deposit Size/Total Deposit/Remaining/
# Extraction Difficulty/Extraction Rate/Status/Est. Time to Deplete/
# Estimated Energy Usage, then BEGIN EXTRACTION. Same popup shell as
# ActivityDetailPanel/SurveyReportPanel (UIPanel + centered) — this is
# Mining's own "confirm before committing" step, since mining is a
# deliberate per-material choice (never "extract everything at once" — see
# the user's own framing when this was designed).
#
# Mining is a CONTINUOUS operation (runs until STOP/departure/depletion —
# see Operations._tick_mining), not a single fixed-duration action, so there
# is no "Mining Duration" to show up front the way a Survey has — Extraction
# Rate (units/sec) and Est. Time to Deplete (how long the CURRENT
# remaining_fraction would last at that rate) are the honest equivalents.
# Total Deposit is intentionally a big, satisfying number (Deposits.
# TOTAL_UNITS_BY_SIZE) — "10 Iron" read far too small for operations at this
# scale.

signal begin_requested(body_id: String, material_name: String)

const PANEL_WIDTH := 380.0

var _panel: UIPanel
var _title_label: Label
var _size_value: Label
var _total_value: Label
var _remaining_value: Label
var _difficulty_value: Label
var _rate_value: Label
var _status_value: Label
var _time_to_deplete_value: Label
var _energy_value: Label
var _begin_btn: UIButton
var _body_id: String = ""
var _material_name: String = ""


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

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_title_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.5)
	vbox.add_child(divider)

	_size_value = _add_field(vbox, "Deposit Size")
	_total_value = _add_field(vbox, "Total Deposit")
	_remaining_value = _add_field(vbox, "Remaining")
	_difficulty_value = _add_field(vbox, "Extraction Difficulty")
	_rate_value = _add_field(vbox, "Extraction Rate")
	_status_value = _add_field(vbox, "Status")
	_time_to_deplete_value = _add_field(vbox, "Est. Time to Deplete")
	_energy_value = _add_field(vbox, "Estimated Energy Usage")

	vbox.add_child(HSeparator.new())

	_begin_btn = UIButton.new()
	_begin_btn.text = "BEGIN EXTRACTION"
	_begin_btn.solid = true
	_begin_btn.shimmer_enabled = false
	_begin_btn.custom_minimum_size = Vector2(0, 36)
	_begin_btn.pressed.connect(_on_begin_pressed)
	vbox.add_child(_begin_btn)

	var cancel := UIButton.new()
	cancel.text = "Cancel"
	cancel.dim = true
	cancel.custom_minimum_size = Vector2(0, 30)
	cancel.pressed.connect(_panel.close_animated)
	vbox.add_child(cancel)


# Two-column row (label left, value right) — mirrors ActivityDetailPanel's
# own _add_field.
func _add_field(parent: VBoxContainer, label_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", UITheme.text)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return val


# ship_busy — true if a DIFFERENT operation is already running (Operations'
# "single operation at a time" constraint) — disables BEGIN and shows a busy
# status instead of Ready, same as ActivityDetailPanel.open_for. Cargo-full
# (Deposits.is_cargo_full) is checked here too, independent of ship_busy —
# a full hold blocks starting a NEW extraction the same way a running one
# does, even with nothing else in progress.
func open_for(body_id: String, material_name: String, ship_busy: bool) -> void:
	var deposit := Deposits.deposit_for(body_id, material_name)
	if deposit == null:
		return

	_body_id = body_id
	_material_name = material_name
	var cargo_full := Deposits.is_cargo_full()

	_title_label.text = material_name.to_upper()
	_size_value.text = deposit.deposit_size
	# Deposits.total_units(), not the raw TOTAL_UNITS_BY_SIZE tier lookup —
	# the actual (size-scaled) total this specific body's deposit holds, not
	# the same number every body of this tier would show regardless of size.
	_total_value.text = "%s units" % Deposits.format_units(Deposits.total_units(deposit))
	_remaining_value.text = "%d%%" % roundi(deposit.remaining_fraction * 100.0)
	_difficulty_value.text = deposit.extraction_difficulty
	var rate := Deposits.extraction_rate_per_second(deposit)
	_rate_value.text = "%.1f/sec" % rate
	_status_value.text = "Cargo Full" if cargo_full else ("Ship Busy" if ship_busy else "Ready")
	_begin_btn.disabled = ship_busy or cargo_full
	var depletion_rate := Deposits.depletion_rate_per_second(deposit)
	var seconds_left := deposit.remaining_fraction / depletion_rate if depletion_rate > 0.0 else 0.0
	_time_to_deplete_value.text = ActivityDef.format_duration(roundi(seconds_left))
	_energy_value.text = Deposits.energy_usage_label(deposit)

	_panel.open_animated()


func _on_begin_pressed() -> void:
	_panel.close_animated()
	begin_requested.emit(_body_id, _material_name)
