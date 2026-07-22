class_name StructuresReadout
extends Control

# Compact "what's already running here" readout — left side of the Cockpit
# screen, starting about a third of the way down. BuildingsPanel used to
# carry a STRUCTURES HERE section for this same information, but that only
# showed while the modal was open; this surfaces it ambiently instead, same
# "always worth a glance, no menu to open" reasoning ShipStatusStrip's CARGO
# line gets on the opposite corner. BuildingsPanel no longer shows built
# structures at all (see its own class comment) — this readout is now the
# ONLY place they show, not a second copy of the same list.
#
# Two lines per structure — name, then a compact rate/produced line — plain
# Labels in a VBoxContainer, no card/border, matching ShipStatusStrip's own
# "ambient readout, not a panel" treatment. Rebuilds from scratch (not
# per-row diffing) on every location change and every structure_constructed
# — the list is short and both fire rarely, same cost/benefit
# ActivitiesPanel's own _rebuild_rows already accepts elsewhere.

const LEFT_MARGIN := 24.0
const TOP_FRACTION := 1.0 / 3.0
const ROW_GAP := 10  # int — add_theme_constant_override wants int, not float
const LINE_GAP := 1  # int — add_theme_constant_override wants int, not float

var _vbox: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", ROW_GAP)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)

	PlayerState.location_changed.connect(_rebuild)
	# Departure hides the list (it describes the place you're LEAVING); arrival's
	# location_changed repopulates it. Both route through _rebuild, whose
	# is_traveling guard is what actually does the hiding — see there.
	PlayerState.travel_started.connect(_rebuild)
	Buildings.structure_constructed.connect(func(_category_id: String, _body_id: String) -> void: _rebuild())
	_rebuild()


# Only the running PRODUCED totals (and the rate, in case a fresh survey
# nudged the native rate mid-visit) need live polling — the name is constant
# for the duration of a stay, same split BuildingsPanel's own STRUCTURES HERE
# cards used to make before this replaced them.
func _process(_delta: float) -> void:
	for row in _vbox.get_children():
		if not row.has_meta("structure_total_label"):
			continue
		var total_label: Label = row.get_meta("structure_total_label")
		if not is_instance_valid(total_label):
			continue
		var cat: String = row.get_meta("structure_category_id")
		var body: String = row.get_meta("structure_body_id")
		var rate := Buildings.knowledge_per_second(cat, body)
		total_label.text = "%.3f %s / sec, Produced: %d" % [
				rate, _category_label(cat), int(Buildings.total_contributed(cat, body))]
	_layout_left()


func _category_label(category_id: String) -> String:
	var label: String = KnowledgeBar.CATEGORY_LABELS.get(category_id, category_id.capitalize())
	return label.capitalize()


func _rebuild() -> void:
	for child in _vbox.get_children():
		child.queue_free()

	# In transit the readout would describe the place you LEFT, so stay hidden
	# until arrival. Guarding here (not only on the travel_started signal) is
	# what covers the common case where the Cockpit — and this node — are created
	# mid-trip because GO was pressed from another view: _ready()'s own _rebuild()
	# would otherwise repopulate the departure location's structures. is_traveling
	# is cleared before arrival's location_changed fires, so the readout reshows.
	if PlayerState.is_traveling:
		visible = false
		return

	var body_id := PlayerState.location_id
	for category_id: String in Buildings.category_ids():
		if Buildings.tier_at(category_id, body_id) >= 0:
			_vbox.add_child(_build_row(category_id, body_id))

	visible = _vbox.get_child_count() > 0


func _build_row(category_id: String, body_id: String) -> Control:
	var def := Buildings.current_building_def(category_id, body_id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LINE_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = def.display_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	# Transfer Station (2026-07-19) has no knowledge rate at all (multiplier
	# 0.0 — it's a logistics gate, not a research building), so "0.000 .../
	# sec, Produced: 0" would just read as broken rather than informative.
	# Skipping the rate label entirely also means _process's own update
	# loop naturally leaves this row alone (it's gated on the SAME
	# "structure_total_label" meta this only sets for the categories that
	# actually have a rate to report).
	if category_id != "transfer_station":
		var total_label := Label.new()
		total_label.add_theme_font_size_override("font_size", 11)
		total_label.add_theme_color_override("font_color", UITheme.dim)
		UITheme.style_label_shadow(total_label)
		total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(total_label)
		box.set_meta("structure_total_label", total_label)

	box.set_meta("structure_category_id", category_id)
	box.set_meta("structure_body_id", body_id)
	return box


# Same "set size, then position (Godot preserves size while moving)"
# technique ShipStatusStrip/ViewSwitcher use for their own screen-edge
# corners — recomputed every frame here since the row count (and therefore
# height) can change on any frame, not just once at startup.
func _layout_left() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	size = _vbox.size
	position = Vector2(LEFT_MARGIN, viewport_size.y * TOP_FRACTION)
