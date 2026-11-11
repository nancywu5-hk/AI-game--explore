## AirTerrain - Default terrain for air/no terrain
##
## Applies air resistance (damping) to slow down movement over time.
## This simulates natural energy loss when swinging or moving through air.
class_name AirTerrain
extends Terrain

# === EXPORTED VARIABLES ===
# Removed exports in favor of Tweakables

# === PUBLIC VARIABLES ===
var air_resistance: float
var applies_to_grappling: bool

# === BUILT-IN METHODS ===
func _init() -> void:
	terrain_name = "Air"

func _ready() -> void:
	# Note: We intentionally do NOT call super._ready() because AirTerrain
	# is a global/default terrain without a DetectionArea (Area2D).
	# super._ready() would try to find one and push a warning if missing.

	affects_movement = true
	_setup_tweakables()

func _setup_tweakables() -> void:
	air_resistance = 0.98
	applies_to_grappling = true
	# TerrainConstants.value_changed.connect(_on_tweakable_changed)

func _on_tweakable_changed(category: String, key: String, value: Variant) -> void:
	if category == "Air":
		match key:
			"air_resistance": air_resistance = float(value)
			"applies_to_grappling": applies_to_grappling = bool(value)

# === OVERRIDDEN METHODS ===

func _calculate_terrain_effect(delta: float, character_position: Vector2) -> Vector2:
	# Air resistance doesn't add force, it reduces velocity (via damping)
	return Vector2.ZERO

## Get the damping factor for air resistance
func get_damping_factor() -> float:
	return air_resistance
