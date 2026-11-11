class_name BaseMenu
extends Node

const MIN_BUTTON_WIDTH := 220.0
const MAX_BUTTON_WIDTH := 800.0
const MIN_BUTTON_HEIGHT := 72.0
const MAX_BUTTON_HEIGHT := 150.0
const MIN_BUTTON_FONT_SIZE := 28
const MAX_BUTTON_FONT_SIZE := 80

var _buttons_to_resize: Array[Control] = []
var _auto_resize_buttons: bool = true

# UI theme helper removed (using Global Theme)

func _ready() -> void:
	get_tree().root.size_changed.connect(_update_button_sizes)
	# Defer to ensure all children are ready and registered
	if _auto_resize_buttons:
		call_deferred("_update_button_sizes")

func register_buttons(buttons: Array[Control], apply_style: bool = true, auto_resize: bool = true) -> void:
	# Apply sizing and modern rounded styles to registered buttons
	_auto_resize_buttons = auto_resize
	_buttons_to_resize.append_array(buttons)
	if apply_style:
		for btn in buttons:
			if btn and btn is Button:
				# Global Theme handles styling now
				pass

	if _auto_resize_buttons:
		_update_button_sizes()

func _update_button_sizes() -> void:
	if not _auto_resize_buttons:
		return
	var metrics: Dictionary = _get_responsive_metrics()
	var button_width := float(metrics["button_width"])
	var button_height := float(metrics["button_height"])
	var button_font_size := int(metrics["button_font_size"])
	for btn in _buttons_to_resize:
		if is_instance_valid(btn):
			btn.custom_minimum_size = Vector2(button_width, button_height)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			if btn is Button:
				btn.add_theme_font_size_override("font_size", button_font_size)

func _get_responsive_metrics() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var base_size: float = min(viewport_size.x, viewport_size.y)
	var button_width := clampf(viewport_size.x * 0.55, MIN_BUTTON_WIDTH, MAX_BUTTON_WIDTH)
	var button_height := clampf(viewport_size.y * 0.12, MIN_BUTTON_HEIGHT, MAX_BUTTON_HEIGHT)
	var button_font_size := int(clampf(base_size * 0.055, MIN_BUTTON_FONT_SIZE, MAX_BUTTON_FONT_SIZE))
	return {
		"button_width": button_width,
		"button_height": button_height,
		"button_font_size": button_font_size,
		"panel_margin_x": clampf(viewport_size.x * 0.06, 24.0, 200.0),
		"panel_margin_y": clampf(viewport_size.y * 0.07, 24.0, 100.0),
		"title_font_size": int(clampf(base_size * 0.09, 48.0, 150.0))
	}

func _on_settings_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	UIManager.open(&"settings")
