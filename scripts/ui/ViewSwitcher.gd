class_name ViewSwitcher
extends Control

# Top-center row of scope tabs (Cockpit / Solar System / ...). Deliberately
# separate from the bottom console — switching which scope you're looking
# at is a camera/perspective change, not a ship action, so it doesn't
# belong mixed in with the console's action pads (see the cockpit-console
# and view-switcher conversations in parallax-core-design-decisions memory).
#
# Data-driven off VIEWS so a new scope tier later (Object/surface view, ...)
# is one array entry, not new layout code — the row just grows via
# HBoxContainer instead of needing hand-placed positions. Entries with an
# empty scene path have no scene built yet — same "leave it active, no-op"
# convention as the console's not-yet-wired buttons: fully clickable, just
# does nothing (UIButton's own press feedback still plays).

signal view_selected(scene_path: String)

const VIEWS: Array[Dictionary] = [
	{"id": "cockpit", "label": "COCKPIT", "scene": "res://scenes/cockpit.tscn"},
	{"id": "solar_system", "label": "SOLAR SYSTEM", "scene": "res://scenes/system_view.tscn"},
	{"id": "planetary", "label": "PLANETARY", "scene": ""},
	{"id": "stellar", "label": "STELLAR", "scene": ""},
	{"id": "galactic", "label": "GALACTIC", "scene": ""},
]

const TAB_GAP := 4
const UNDERLINE_HEIGHT := 2.0

var _tabs: Dictionary = {}        # id -> UIButton
var _underlines: Dictionary = {}  # id -> ColorRect
var _active_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_top = 20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TAB_GAP)
	add_child(row)

	for view: Dictionary in VIEWS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		row.add_child(cell)

		var btn := UIButton.new()
		btn.text = view["label"]
		btn.dim = true
		btn.shimmer_enabled = false
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_tab_pressed.bind(view["id"], view["scene"]))
		cell.add_child(btn)

		var underline := ColorRect.new()
		underline.custom_minimum_size = Vector2(0, UNDERLINE_HEIGHT)
		underline.color = UITheme.accent
		underline.modulate.a = 0.0
		cell.add_child(underline)

		_tabs[view["id"]] = btn
		_underlines[view["id"]] = underline


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
	if scene == "" or id == _active_id:
		return
	view_selected.emit(scene)
