class_name LockButton
extends Control

# Small reusable "lock this target as the destination" toggle — sits right
# under ScanPrompt in the callout's unified panel. Independent of scanning
# (see the lock-destination design conversation in parallax-core-design-
# decisions memory) — you can lock a destination without ever scanning it,
# scan without locking, or both. Fully self-contained: reads/writes the
# Destination autoload directly rather than routing through the owning view
# script, and relabels itself LOCK/UNLOCK by listening for
# Destination.destination_changed, since (unlike ScanPrompt) there's no
# animation for a caller to coordinate — pressing it is instant.

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
	_button.press_sfx = "lock_button"  # override — LOCK/UNLOCK gets its own distinct sound instead of the generic button click, see AudioManager.ui_confirm
	_button.pressed.connect(_on_pressed)
	add_child(_button)

	Destination.destination_changed.connect(_refresh_label)


# Call once per newly-focused target.
func present(id: String) -> void:
	_id = id
	_button.visible = true
	_refresh_label()


func reset() -> void:
	_id = ""
	_button.visible = false


func _on_pressed() -> void:
	if Destination.is_locked(_id):
		Destination.clear()
	else:
		Destination.lock(_id)


func _refresh_label() -> void:
	if _id == "":
		return
	_button.text = "UNLOCK" if Destination.is_locked(_id) else "LOCK"
