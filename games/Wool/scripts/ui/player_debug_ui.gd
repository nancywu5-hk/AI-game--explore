class_name PlayerDebugUI
extends CanvasLayer

var _player: BasePlayer
var _label: Label

func setup(player: BasePlayer) -> void:
	_player = player
	_setup_label()
	update_ui()

func _setup_label() -> void:
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.z_index = 1000
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 2)
	add_child(_label)

func update_ui() -> void:
	if not _player or not _label:
		return

	var text: String = "=== FEATURES ===\n"

	# 1. DoubleJump
	text += _get_feature_status_text(KEY_1, _player.double_jump_feature, "DoubleJump")
	# 2. Glide
	text += _get_feature_status_text(KEY_2, _player.glide_feature, "Glide")
	# 3. Grappling
	text += _get_feature_status_text(KEY_3, _player.grappling_feature, "Grappling")
	# 4. Wings
	text += _get_feature_status_text(KEY_4, _player.wings_feature, "Wings")

	# Terrain
	if _player.current_terrain:
		text += "\n=== TERRAIN ===\n"
		text += "%s: ON" % _player.current_terrain.terrain_name

	_label.text = text

func _get_feature_status_text(key_code: int, feature: Feature, name: String, action_key: String = "") -> String:
	var key_str = OS.get_keycode_string(key_code).replace("Key ", "") # e.g. "1"
	# Or just use the number since we know it
	if key_code >= KEY_0 and key_code <= KEY_9:
		key_str = str(key_code - KEY_0)

	if feature:
		var status: String = "ON" if feature.enabled else "OFF"
		var extra: String = ""
		if action_key != "":
			extra = " (Action: %s)" % action_key
		return "[%s] %s: %s%s\n" % [key_str, name, status, extra]
	else:
		return "[%s] %s: NOT FOUND\n" % [key_str, name]
