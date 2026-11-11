class_name BoostNail
extends BaseNail

@export var boost_multiplier: float = 2.5

func _setup_interaction() -> void:
	interaction_name = "BoostNail"
	_update_visual()

func get_boost_multiplier() -> float:
	return boost_multiplier
