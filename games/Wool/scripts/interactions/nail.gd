class_name NormalNail
extends BaseNail

func _setup_interaction() -> void:
	interaction_name = "Nail"
	
	# Load colors from constants
	normal_color = InteractionConstants.get_value("Visuals", "nail_color", InteractionConstants.DEFAULT_NORMAL_COLOR)
	highlight_color = InteractionConstants.get_value("Visuals", "highlight_nail_color", InteractionConstants.DEFAULT_HIGHLIGHT_COLOR)
	
	_update_visual()

func _setup_tweakables() -> void:
	if not InteractionConstants.value_changed.is_connected(_on_tweakable_changed):
		InteractionConstants.value_changed.connect(_on_tweakable_changed)
	_update_visual()

func _on_tweakable_changed(category: String, key: String, value: Variant) -> void:
	if category == "Visuals":
		match key:
			"highlight_nail_color":
				highlight_color = value
				_update_visual()
			"nail_color":
				normal_color = value
				_update_visual()

func _update_visual() -> void:
	# Modulate both sprites
	var color = highlight_color if is_active else normal_color
	
	var back = get_node_or_null(NODE_BACK_SPRITE)
	if back: back.modulate = color
	
	var front = get_node_or_null(NODE_FRONT_SPRITE)
	if front: front.modulate = color

	# Legacy support if user hasn't updated scene strictly yet
	var legacy_sprite = get_node_or_null("Sprite2D")
	if legacy_sprite: legacy_sprite.modulate = color
