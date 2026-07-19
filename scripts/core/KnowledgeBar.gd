class_name KnowledgeBar
extends HBoxContainer

# Always-visible top bar showing all 6 Buildings Knowledge categories
# (Docs/Buildings System.md) — "watch your numbers go up as you build" per
# the original design conversation. "geological", "astrophysics",
# "life_sciences", "anomalies", and "atmospheric" all accrue via real
# buildings now — only "engineering" doesn't (deliberately has no building
# category at all, only a flat per-construction bonus) and sits at whatever
# Research.knowledge already holds from that bonus alone.
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

# Same count-up idiom as HUD's _credits_label (see _on_balance_changed there):
# ticks arrive in rapid, uneven succession (every whole Knowledge point,
# across however many structures happen to be running), so each tick restarts
# the tween from whatever the label currently shows rather than from the true
# total, and a fresh tick mid-count just redirects it instead of stacking.
const COUNT_SECONDS := 0.6

var _name_labels: Dictionary = {}   # category_id -> Label
var _value_labels: Dictionary = {}  # category_id -> Label
var _display_values: Dictionary = {}  # category_id -> int, value currently shown mid-count
var _tweens: Dictionary = {}  # category_id -> Tween


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
		_display_values[category_id] = Research.knowledge(category_id)

	Research.knowledge_changed.connect(_on_knowledge_changed)
	UITheme.theme_changed.connect(_on_theme_changed)


func _on_knowledge_changed(category_id: String, new_total: int) -> void:
	var existing_tween: Tween = _tweens.get(category_id)
	if existing_tween != null and existing_tween.is_valid():
		existing_tween.kill()
	var start_value: int = _display_values.get(category_id, new_total)
	var tween := create_tween()
	tween.tween_method(_set_display_value.bind(category_id), start_value, new_total, COUNT_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tweens[category_id] = tween


func _set_display_value(value: int, category_id: String) -> void:
	_display_values[category_id] = value
	var label: Label = _value_labels.get(category_id)
	if label != null:
		label.text = str(value)


func _on_theme_changed() -> void:
	for category_id: String in _name_labels:
		(_name_labels[category_id] as Label).add_theme_color_override("font_color", UITheme.dim)
	for category_id: String in _value_labels:
		(_value_labels[category_id] as Label).add_theme_color_override("font_color", UITheme.text)
