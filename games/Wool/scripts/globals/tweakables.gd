extends Node

## Tweakables - Registry for all configuration singletons
##
## Aggregates all specific constant autoloads for the SettingsWindow.
## Acts as a facade for backward compatibility if needed, but direct access
## to specific constants (e.g. CharacterConstants.get_value) is preferred.

var registries: Array[BaseConstants] = []

func _ready() -> void:
	# Wait for other autoloads to be ready
	call_deferred("_register_autoloads")

func _register_autoloads() -> void:
	registries.append(CharacterConstants)
	registries.append(FeatureConstants)
	registries.append(InteractionConstants)
	registries.append(TerrainConstants)
	registries.append(WorldConstants)

# Helper to find which registry holds a category (for backward compat or UI)
func get_registry_for_category(category: String) -> BaseConstants:
	for reg in registries:
		if reg.settings.has(category):
			return reg
	return null

# Facade methods (optional, but keeps old code working if we wanted)
# But we will refactor the code to use specific constants directly.
