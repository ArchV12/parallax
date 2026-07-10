class_name ScanPrompt
extends Control

# Small reusable "target unscanned -> press to scan" trigger — the recurring
# interaction for revealing gated info about a targeted thing (a planet's
# data panel today; moons/signals/surface scans later will want this exact
# shape, per the scanning design conversation in parallax-core-design-
# decisions memory). Deliberately dumb: just a button that knows whether to
# say SCAN or RESCAN — it doesn't run the scan itself or know what scanning
# reveals. The scanning animation (progress bar, "Scanning...") lives in
# BodyInfoPanel now, not here, so it happens on the actual data panel
# instead of a second floating element next to this one.

signal pressed_for(id: String)

const BUTTON_SIZE := Vector2(90.0, 28.0)

var _button: UIButton
var _id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE  # not inside a Container — needs an explicit size, not just a minimum-size hint, so callers can reliably read it back (e.g. for the callout's backdrop rect)

	_button = UIButton.new()
	_button.solid = true
	_button.shimmer_enabled = false
	_button.custom_minimum_size = BUTTON_SIZE
	_button.add_theme_font_size_override("font_size", 12)
	_button.visible = false
	_button.pressed.connect(func() -> void: pressed_for.emit(_id))
	add_child(_button)


# Call once per newly-focused target — always shows the button, labeled
# SCAN for a first look or RESCAN if Discoveries already has this id (a
# scanner upgrade might reveal more later, even though multiple reveal
# tiers aren't built yet). The caller is responsible for also showing
# existing data immediately when already scanned — this widget only ever
# drives the button.
func present(id: String) -> void:
	_id = id
	_button.text = "RESCAN" if Discoveries.is_scanned(id) else "SCAN"
	_button.visible = true


# Clears the button — no target focused anymore, or focus moved to
# something else.
func reset() -> void:
	_id = ""
	_button.visible = false


# Called once BodyInfoPanel's scan animation finishes, so the button is
# already labeled RESCAN if you look at this same target again without
# reselecting it.
func mark_scanned() -> void:
	_button.text = "RESCAN"
