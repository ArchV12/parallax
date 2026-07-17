class_name ViewSwitcher
extends Control

# Bottom-right row of scope tabs (Cockpit / Solar System / ...) — moved out
# of the crowded top band (system/credits/year/knowledge-bar all competing
# for the same space) to its own quiet corner. Deliberately separate from
# CommandMenu's fan (bottom-center) — switching which scope you're looking
# at is a camera/perspective change, not a ship action, so it doesn't belong
# mixed in with the command menu's action leaves either (see the cockpit-
# console and view-switcher conversations in parallax-core-design-decisions
# memory).
#
# Data-driven off VIEWS so a new scope tier later (Object/surface view, ...)
# is one array entry, not new layout code — the row just grows via
# HBoxContainer instead of needing hand-placed positions. Entries with an
# empty scene path have no scene built yet — same "leave it active, no-op"
# convention as the console's not-yet-wired buttons: fully clickable, just
# does nothing (UIButton's own press feedback still plays).

signal view_selected(scene_path: String)
# Fired instead of view_selected when the ALREADY-active tab is clicked
# again — a same-scene no-op for most tabs, but HUD relays it as a
# "recenter" request for whichever view actually has one (System view's
# free-fly camera, see HUD.recenter_requested).
signal active_tab_reclicked(id: String)

const VIEWS: Array[Dictionary] = [
	{"id": "cockpit", "label": "COCKPIT", "scene": "res://scenes/cockpit.tscn"},
	{"id": "solar_system", "label": "SOLAR SYSTEM", "scene": "res://scenes/system_view.tscn"},
	{"id": "planetary", "label": "PLANETARY", "scene": "res://scenes/planetary_system_view.tscn"},  # not routed generically — see _on_tab_pressed, this needs a resolved planet name first
	{"id": "stellar", "label": "STELLAR", "scene": ""},
	{"id": "galactic", "label": "GALACTIC", "scene": ""},
]

const TAB_GAP := 4
const UNDERLINE_HEIGHT := 2.0
const CORNER_MARGIN := 24.0

var _tabs: Dictionary = {}        # id -> UIButton
var _underlines: Dictionary = {}  # id -> ColorRect
var _active_id: String = ""
var _row: HBoxContainer


func _ready() -> void:
	# Anchors/offsets are left at their Control default (all 0 — top-left,
	# zero-size) deliberately; final position/size is computed explicitly in
	# _layout_bottom_right below, once. Using set_anchors_and_offsets_preset
	# here (as a first attempt did) computes offsets from THIS control's
	# size at the moment it's called — before _row has any tab children,
	# that's still (0,0), which put the row's TOP-LEFT at the corner instead
	# of growing the whole row from its own bottom-right.
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", TAB_GAP)
	add_child(_row)

	for view: Dictionary in VIEWS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		_row.add_child(cell)

		var btn := UIButton.new()
		btn.text = view["label"]
		btn.dim = true
		btn.shimmer_enabled = false
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 12)
		if view["scene"] == "":  # STELLAR/GALACTIC — no scene built yet, a genuine no-op (see class comment), so it should sound like one
			btn.press_sfx = "error"
		btn.pressed.connect(_on_tab_pressed.bind(view["id"], view["scene"]))
		cell.add_child(btn)

		var underline := ColorRect.new()
		underline.custom_minimum_size = Vector2(0, UNDERLINE_HEIGHT)
		underline.color = UITheme.accent
		underline.modulate.a = 0.0
		cell.add_child(underline)

		_tabs[view["id"]] = btn
		_underlines[view["id"]] = underline

	# Deferred one frame so _row (an HBoxContainer) has actually run Godot's
	# own container-sort pass and reports its REAL size — same reasoning
	# HUD._layout_knowledge_bar already defers for.
	call_deferred("_layout_bottom_right")


# Positions the whole row by its own actual size so its BOTTOM-RIGHT corner
# lands at the screen's bottom-right corner (minus CORNER_MARGIN) — sets
# `size` first (establishing the box's dimensions from _row's real minimum
# size), then `position` (which Godot's Control.position setter moves while
# PRESERVING the size just set), rather than fighting the anchor/offset
# system directly.
func _layout_bottom_right() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	size = _row.size
	position = viewport_size - _row.size - Vector2(CORNER_MARGIN, CORNER_MARGIN)


# A specific tab's own button — general accessor, kept public for whatever
# future caller needs a tab's real rendered rect (HUD's Credits label used to
# be one, before the tab row moved to the bottom-right corner).
func get_tab_button(id: String) -> UIButton:
	return _tabs.get(id)


func set_active(id: String) -> void:
	if not _tabs.has(id) or id == _active_id:
		return
	_active_id = id
	for tab_id: String in _tabs.keys():
		var active := tab_id == id
		var btn: UIButton = _tabs[tab_id]
		btn.add_theme_color_override("font_color", UITheme.accent if active else UITheme.dim)
		(_underlines[tab_id] as ColorRect).modulate.a = 1.0 if active else 0.0


func _on_tab_pressed(id: String, scene: String) -> void:
	if id == _active_id:
		active_tab_reclicked.emit(id)
		return
	# PLANETARY jumps straight into whatever planetary system you're
	# currently relevant to — the planet you're orbiting, or the parent of
	# the moon you're orbiting — rather than a fixed scene, so it can't
	# route through the generic scene-path emit below (see
	# HUD.go_to_planetary_system, which needs that planet name up front).
	# Still offered for a moonless planet (Mercury/Venus/...) — showing an
	# empty system is far less confusing than a tab that mysteriously does
	# nothing with no way to tell why.
	if id == "planetary":
		HUD.go_to_planetary_system(_current_planet_for_view())
		return
	if scene == "":
		return
	view_selected.emit(scene)


# Whatever planet PLANETARY should open on: the body you're currently
# orbiting itself if it's a planet (or Sol), or its parent planet if you're
# at one of its moons — see KnownBodies.Entry.parent.
func _current_planet_for_view() -> String:
	var entry := KnownBodies.get_entry(PlayerState.location_id)
	if entry == null:
		return "Earth"
	return entry.parent if entry.parent != "" else entry.body_name
