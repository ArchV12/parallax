class_name KnowledgeBar
extends HBoxContainer

# Always-visible top bar showing all 6 Buildings Knowledge categories
# (Docs/Buildings System.md) — "watch your numbers go up as you build" per
# the original design conversation. Only "geological" actually accrues via
# real buildings this phase; the other 5 sit at whatever Research.knowledge
# already holds (0, since nothing feeds them yet) and are included now so
# the bar doesn't need reshaping once they come online in a later phase.
#
# Deliberately excludes the pre-existing "resource" category (Resource
# Survey -> Mining materials) — a separate, older system, not one of the six
# Knowledge domains this bar tracks.
#
# Updated per-tile via Research.knowledge_changed, never rebuilt — same
# single-source-of-truth-signal idiom HUD's own _credits_label uses against
# Economy.balance_changed.

const CATEGORY_IDS := ["geological", "atmospheric", "life_sciences", "astrophysics", "anomalies", "engineering"]
const CATEGORY_LABELS := {
	"geological": "GEOLOGY",
	"atmospheric": "ATMOSPHERE",
	"life_sciences": "LIFE SCI",
	"astrophysics": "ASTROPHYSICS",
	"anomalies": "ANOMALIES",
	"engineering": "ENGINEERING",
}

var _name_labels: Dictionary = {}   # category_id -> Label
var _value_labels: Dictionary = {}  # category_id -> Label


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for category_id: String in CATEGORY_IDS:
		var tile := VBoxContainer.new()
		tile.add_theme_constant_override("separation", 0)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tile)

		var name_label := Label.new()
		name_label.text = CATEGORY_LABELS[category_id]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", UITheme.dim)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(name_label)
		_name_labels[category_id] = name_label

		var value_label := Label.new()
		value_label.text = str(Research.knowledge(category_id))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override("font_size", 14)
		value_label.add_theme_color_override("font_color", UITheme.text)
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(value_label)
		_value_labels[category_id] = value_label

	Research.knowledge_changed.connect(_on_knowledge_changed)
	UITheme.theme_changed.connect(_on_theme_changed)


func _on_knowledge_changed(category_id: String, new_total: int) -> void:
	var label: Label = _value_labels.get(category_id)
	if label != null:
		label.text = str(new_total)


func _on_theme_changed() -> void:
	for category_id: String in _name_labels:
		(_name_labels[category_id] as Label).add_theme_color_override("font_color", UITheme.dim)
	for category_id: String in _value_labels:
		(_value_labels[category_id] as Label).add_theme_color_override("font_color", UITheme.text)
