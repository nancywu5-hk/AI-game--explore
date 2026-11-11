## Feature - Abstract Base Class
##
## Base class for all character features (wings, grappling, push, etc.)
## Features are components that modify character physics/behavior.
##
## Features inherit from PhysicsChanger and are managed by the Character.
## They can be activated/deactivated based on game state (e.g., nearby interactions).
##
## Auto-Registration: Features automatically register themselves with their parent BaseCharacter in _ready()
class_name Feature
extends PhysicsChanger

# === SIGNALS ===
signal feature_activated()
signal feature_deactivated()
signal enabled_changed(enabled: bool)

# === EXPORTED VARIABLES ===
@export var feature_name: String = "UnnamedFeature"
@export var enabled: bool = true:
	set(value):
		if enabled != value:
			enabled = value
			enabled_changed.emit(enabled)
@export var auto_register: bool = true  # Automatically register with parent character
@export var drop_icon: Texture2D = null # Icon to display when dropped as item

# === PRIVATE VARIABLES ===
var _active: bool = false
var _character: Node = null  # Reference to owning character (typed as Node to avoid cyclic dependency)

# === BUILT-IN METHODS ===
func _ready() -> void:
	if auto_register:
		_register_with_character()

# === PUBLIC METHODS ===

## Setup tweakable values from Autoload using a dictionary mapping
## @param config: A Dictionary mapping "settings_key" -> "script_property_name"
## @param category: The category name in FeatureConstants (defaults to feature_name)
## @param skip_initial_load_keys: List of config keys to exclude from initial value loading (preserves Inspector values)
func setup_tweakables_generic(config: Dictionary, category: String = "", skip_initial_load_keys: Array[String] = []) -> void:
	if category == "":
		category = feature_name

	# Initial Load
	for key in config:
		# Skip keys explicitly requested to preserve Inspector values
		if key in skip_initial_load_keys:
			continue

		var property_name: String = config[key]
		var val = FeatureConstants.get_value(category, key)
		if val != null:
			set(property_name, val)

	# Connect signal
	if not FeatureConstants.value_changed.is_connected(_on_generic_tweakable_changed):
		FeatureConstants.value_changed.connect(_on_generic_tweakable_changed.bind(config, category))

func _on_generic_tweakable_changed(changed_category: String, key: String, value: Variant, config: Dictionary, target_category: String) -> void:
	if changed_category != target_category:
		return

	if key in config:
		var property: String = config[key]
		# Use explicit casting if possible, or rely on Variant assignment
		# For type safety, we assume the Property type matches the Value type
		set(property, value)

## Get the character that owns this feature
func get_character() -> Node:
	return _character

## Activate this feature (called by Character)
func activate() -> void:
	if not enabled:

		return

	_active = true

	_on_activated()
	feature_activated.emit()

## Trigger the feature's primary action (used by AI or manual calls)
## Override this in specific features (e.g. DoubleJump)
func trigger() -> void:
	pass

## Deactivate this feature (called by Character)
func deactivate() -> void:
	_active = false
	_on_deactivated()
	feature_deactivated.emit()

## Check if this feature is currently active
func is_active() -> bool:
	return _active and enabled

# === VIRTUAL METHODS (Override in child classes) ===

## Called when feature is activated - override for custom behavior
func _on_activated() -> void:
	pass

## Called when feature is deactivated - override for custom behavior
func _on_deactivated() -> void:
	pass

## Handle input for this feature - override for input-based features
## @param character: Reference to the character that owns this feature
## This is called during the character's physics processing
func handle_input(character: BaseCharacter) -> void:
	pass  # Override in child classes that need input

## Get gravity multiplier - override to modify fall speed
## @return float: Multiplier for gravity (1.0 = no change, 0.5 = half speed, etc.)
func get_gravity_multiplier() -> float:
	return 1.0  # No modification by default

## Get movement factor - MUST be overridden
## @param delta: The physics delta time
## @param character_position: The current position of the character
## @return Vector2: The movement factor to apply
func get_movement_factor(delta: float, character_position: Vector2) -> Vector2:
	if not is_active():
		return Vector2.ZERO

	return _calculate_movement_factor(delta, character_position)

## Override this in child classes to implement feature-specific physics
func _calculate_movement_factor(_delta: float, _character_position: Vector2) -> Vector2:
	push_error("Feature._calculate_movement_factor() must be overridden in: " + feature_name)
	return Vector2.ZERO

# === PRIVATE METHODS ===

## Automatically find and register with parent BaseCharacter
func _register_with_character() -> void:
	# Walk up the tree to find a BaseCharacter parent
	var node: Node = get_parent()
	var depth = 0
	while node and depth < 5: # Safety limit
		# Use duck typing to avoid cyclic dependency issues with class_name BaseCharacter
		if node.has_method("add_feature"):
			_character = node
			_character.add_feature(self)
			return

		node = node.get_parent()
		depth += 1

	# If no BaseCharacter found, warn user
	push_warning("Feature '%s' could not find a parent with add_feature()! Ensure it's a child (or descendant) of a BaseCharacter." % feature_name)
