class_name BaseConstants
extends Node

## BaseConstants - Base class for configuration singletons
##
## Provides storage, access, and signals for runtime configuration.

signal value_changed(section: String, key: String, new_value: Variant)

# Dictionary structure: Section -> Key -> { value, min, max, step, type, desc }
var settings: Dictionary = {}

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if settings.has(section) and settings[section].has(key):
		return settings[section][key]["value"]
	push_warning("Setting not found: %s/%s" % [section, key])
	return default

func set_value(section: String, key: String, value: Variant) -> void:
	if not settings.has(section):
		settings[section] = {}

	if not settings[section].has(key):
		settings[section][key] = { "value": value }
	else:
		settings[section][key]["value"] = value

	value_changed.emit(section, key, value)
