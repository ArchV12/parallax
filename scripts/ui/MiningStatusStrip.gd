class_name MiningStatusStrip
extends Control

# Top-left readout, under HUD's own CREDITS line, visible only while a
# continuous Mining operation is RUNNING — the counterpart to ArrivalScanRow's
# own scan bars for the one Activity that's deliberately NOT auto-fired/
# instant (Docs/Arrival Scan System.md's "what stays manual" section: mining
# is meant to take real time, the player can do other things alongside it).
# Replaces the mining active-card that used to live inside ActivitiesPanel's
# own ACTIVE OPERATIONS section — that whole drawer is gone now that its
# other content (Survey rows) moved to ArrivalScanRow.
#
# Was bottom-right originally, then bottom-left "above the cargo line"
# (ShipStatusStrip's own CARGO readout) — both read as either overlapping
# the bottom-right view-switcher tabs or fighting ShipStatusStrip's own
# dynamic height (its size changes with content, so anything stacked
# directly above it has to either query its live size or guess). Top-left,
# fixed distance under the CREDITS line (HUD._credits_label, itself a
# static offset_top=66 single-line label with nothing else stacked below it
# in this corner) sidesteps both problems — nothing else here is dynamic.
#
# Same "set size, then position (Godot preserves size while moving)"
# technique ShipStatusStrip/StructuresReadout use for their own screen-edge
# corners — recomputed every frame while active, since the label content
# (and therefore size) changes as yield/remaining% tick.

const LEFT_MARGIN := 24.0  # matches HUD._credits_label.offset_left and every other HUD left-edge readout
const TOP_OFFSET := 110.0  # a healthy gap under CREDITS (offset_top 66 + its own single-line height)

var _panel: PanelContainer
var _yield_label: Label
var _remaining_label: Label
var _op_id: String = ""


func _ready() -> void:
	visible = false

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.button
	style.border_color = UITheme.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(190, 0)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	var status_label := Label.new()
	status_label.text = "MINING - EXTRACTING..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", UITheme.accent)
	box.add_child(status_label)

	_yield_label = Label.new()
	_yield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_yield_label.add_theme_font_size_override("font_size", 12)
	_yield_label.add_theme_color_override("font_color", UITheme.text)
	box.add_child(_yield_label)

	_remaining_label = Label.new()
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remaining_label.add_theme_font_size_override("font_size", 11)
	_remaining_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(_remaining_label)

	var stop_btn := UIButton.new()
	stop_btn.text = "STOP"
	stop_btn.solid = true
	stop_btn.shimmer_enabled = false
	stop_btn.custom_minimum_size = Vector2(0, 26)
	stop_btn.add_theme_font_size_override("font_size", 11)
	stop_btn.pressed.connect(func() -> void: Operations.stop_mining(_op_id))
	box.add_child(stop_btn)

	Operations.operation_started.connect(_on_operation_started)
	Operations.operation_stopped.connect(_on_operation_stopped)


func _on_operation_started(op_id: String) -> void:
	var op := Operations.get_operation(op_id)
	if op == null or op.activity_id != "mining":
		return
	_op_id = op_id
	visible = true


func _on_operation_stopped(activity_id: String, _location_id: String, _summary: Dictionary) -> void:
	if activity_id != "mining":
		return
	_op_id = ""
	visible = false


func _process(_delta: float) -> void:
	if _op_id == "":
		return
	var op := Operations.get_operation(_op_id)
	if op == null:
		visible = false
		return

	_yield_label.text = "+%d %s" % [op.mining_session_yield, op.deposit_material]
	var deposit := Deposits.deposit_for(op.location_id, op.deposit_material)
	_remaining_label.text = "Deposit Remaining: %d%%" % roundi((deposit.remaining_fraction if deposit != null else 0.0) * 100.0)

	size = _panel.size
	position = Vector2(LEFT_MARGIN, TOP_OFFSET)
