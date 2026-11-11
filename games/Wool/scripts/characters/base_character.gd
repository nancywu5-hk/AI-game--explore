## BaseCharacter - Abstract Base Class for all Characters
##
## Implements the core character logic according to architecture.excalidraw:
## - Manages list of features
## - Manages current_terrain
## - Manages nearby_interactions
## - Manages skin
## - Iterates over all features to calculate final movement
##
## Both Player and Enemy inherit from this class.
class_name BaseCharacter
extends CharacterBody2D

# === SIGNALS ===
signal feature_added(feature: Feature)
signal feature_removed(feature: Feature)
signal interaction_detected(interaction: Interaction)
signal interaction_lost(interaction: Interaction)
signal terrain_entered(terrain: Terrain)
signal terrain_exited(terrain: Terrain)

# === CONSTANTS ===
# Removed GRAVITY constant in favor of Tweakables

# === EXPORTED VARIABLES ===
@export var skin_resource: CharacterSkin

# === PUBLIC VARIABLES ===
var max_health: int = 1
var move_speed: float
var gravity: float = WorldConstants.DEFAULT_GRAVITY
var _is_grapple_initialized: bool = false
var _grapple_animation_time: float = 0.0  # Time left for grapple position animation
var _grapple_target_position: Vector2 = Vector2.ZERO  # Target position for animation
var _swing_gravity: float = 600.0  # Lower gravity for more natural swinging
var current_health: int = 1
var nearby_interactions: Array[Interaction] = []
var current_terrain: Terrain = null

# === PRIVATE VARIABLES ===
var _features: Array[Feature] = []
var _physics_changers: Array[PhysicsChanger] = []
var _default_air_terrain: AirTerrain = null  # Default terrain for air resistance
var _active_terrains: Array[Terrain] = [] # Stack of active terrains

# === ONREADY VARIABLES ===
@onready var skin: BodySkin = $Skin if has_node("Skin") else null
@onready var physics_shape: CollisionShape2D = $PhysicsShape if has_node("PhysicsShape") else null
@onready var hitbox_area: Area2D = $HitboxArea if has_node("HitboxArea") else null
@onready var features_container: Node = $Features if has_node("Features") else null

# === BUILT-IN METHODS ===
func _ready() -> void:
	_setup_tweakables()
	current_health = max_health
	_setup_default_air_terrain()
	_setup_features()
	_connect_to_interactions()
	_apply_skin()
	_setup_character()

func _physics_process(delta: float) -> void:
	if not is_inside_tree(): # Safety check
		return

	# Apply gravity if not on floor (and terrain allows it)
	var apply_gravity: bool = true
	if current_terrain and not current_terrain.uses_standard_gravity:
		apply_gravity = false

	if apply_gravity and not is_on_floor():
		velocity.y += _calculate_gravity(delta)

	# Calculate movement from all features and physics changers
	var movement_factor: Vector2 = _calculate_all_movement_factors(delta)
	velocity += movement_factor

 	# Apply terrain damping (handled by terrain itself)
	if current_terrain:
		current_terrain.apply_damping(self, delta)

	# Custom physics processing (override in child classes)
	_process_physics(delta)

	# Handle grapple position animation
	if _grapple_animation_time > 0.0:
		_grapple_animation_time -= delta
		if _grapple_animation_time <= 0.0:
			_grapple_animation_time = 0.0
			# Mark grapple as reached
			var grappling = _get_active_grappling()
			if grappling:
				grappling._has_reached_rope_length = true
		else:
			# Calculate target position on the rope
			var grappling = _get_active_grappling()
			if grappling:
				var offset = get_grapple_offset()
				var pivot_pos = global_position + offset
				var to_grapple = _grapple_target_position - pivot_pos
				var direction = to_grapple.normalized()
				var target_pos = _grapple_target_position - direction * grappling.rope_length - offset
				global_position = global_position.lerp(target_pos, 20.0 * delta)  # Faster interpolation

	# Apply swinging constraint
	_apply_grapple_constraint(delta)

	if not is_inside_tree() or is_queued_for_deletion() or not is_physics_processing():
		return

	# Apply movement
	move_and_slide()

func _on_grapple_started(target: Vector2) -> void:
	_is_grapple_initialized = false # Reset on start to force impulse on first constraint frame
	_grapple_animation_time = 0.1  # 0.1 seconds animation time
	_grapple_animation_time = 0.1  # 0.1 seconds animation time
	_grapple_target_position = target
	AudioManager.play_sound(AudioManager.WOOL.HOOK)

func _on_grapple_ended() -> void:
	if _is_grapple_initialized: # Only play release sound if we were actually grappling
		AudioManager.play_sound(AudioManager.WOOL.SCHWINGEN)
	_is_grapple_initialized = false
	# The original diff had `current_anim_state = CharacterConstants.PlayerState.IDLE` here,
	# but `current_anim_state` and `CharacterConstants.PlayerState` are not defined in this BaseCharacter.
	# Assuming this line was intended for a child class (e.g., PlayerCharacter) and removing it
	# to keep the BaseCharacter syntactically correct and faithful to the provided context.

## Setup tweakable values from Autoload
func _setup_tweakables() -> void:
	# Initial load
	move_speed = CharacterConstants.get_value("Player", "move_speed")
	max_health = 1
	gravity = WorldConstants.get_value("Physics", "gravity")

	# Listen for changes
	CharacterConstants.value_changed.connect(_on_tweakable_changed)
	WorldConstants.value_changed.connect(_on_world_tweakable_changed)

func _on_tweakable_changed(category: String, key: String, value: Variant) -> void:
	if category == "Player":
		match key:
			"move_speed":
				move_speed = float(value)
			"max_health":
				max_health = int(value)

func _on_world_tweakable_changed(category: String, key: String, value: Variant) -> void:
	if category == "Physics" and key == "gravity":
		gravity = float(value)

## Add a feature to this character
func add_feature(feature: Feature) -> void:
	if feature in _features:
		push_warning("Feature '%s' already added to character!" % feature.feature_name)
		return

	_features.append(feature)
	_physics_changers.append(feature)

	# Connect grappling signals
	if feature is GrapplingFeature:
		if not feature.grapple_started.is_connected(_on_grapple_started):
			feature.grapple_started.connect(_on_grapple_started)
		if not feature.grapple_ended.is_connected(_on_grapple_ended):
			feature.grapple_ended.connect(_on_grapple_ended)

	feature_added.emit(feature)

## Remove a feature from this character
func remove_feature(feature: Feature) -> void:
	_features.erase(feature)
	_physics_changers.erase(feature)
	feature_removed.emit(feature)

## Get all features
func get_features() -> Array[Feature]:
	return _features.duplicate()

## Get a specific feature by name
func get_feature_by_name(feature_name: String) -> Feature:
	for feature in _features:
		if feature.feature_name == feature_name:
			return feature
	return null

## Get a specific feature by type
func get_feature_by_type(feature_type: Variant) -> Feature:
	var found_feature: Feature = null
	for feature in _features:
		if is_instance_of(feature, feature_type):
			if feature.enabled:
				return feature # Return immediately if enabled
			if found_feature == null:
				found_feature = feature # Keep as fallback
	return found_feature

## Get the active terrain instance of a specific type (e.g. Water terrain by name or specific subclass)
## Returns the most recently added terrain of that type, or null if none active.
func get_active_terrain_of_type(terrain_type: Variant) -> Terrain:
	# Iterate backwards to get the most recent one (standard stack behavior)
	# though for "am I inside water", any water is fine.
	for i in range(_active_terrains.size() - 1, -1, -1):
		var terrain = _active_terrains[i]
		if is_instance_of(terrain, terrain_type):
			return terrain
	return null

## Add an interaction to nearby list
func add_nearby_interaction(interaction: Interaction) -> void:
	if interaction not in nearby_interactions:
		nearby_interactions.append(interaction)
		_on_interaction_detected(interaction)
		interaction_detected.emit(interaction)

## Remove an interaction from nearby list
func remove_nearby_interaction(interaction: Interaction) -> void:
	nearby_interactions.erase(interaction)
	_on_interaction_lost(interaction)
	interaction_lost.emit(interaction)

## Called by Terrain when character enters
func enter_terrain(terrain: Terrain) -> void:
	if terrain not in _active_terrains:
		_active_terrains.append(terrain)
		_update_current_terrain()

## Called by Terrain when character exits
func exit_terrain(terrain: Terrain) -> void:
	_active_terrains.erase(terrain)
	_update_current_terrain()

func _update_current_terrain() -> void:
	if _active_terrains.is_empty():
		set_current_terrain(_default_air_terrain)
	else:
		# Use terrain with highest priority
		# If priorities are equal, prefer the most recently added (last in list)
		var best_terrain: Terrain = _active_terrains.back()

		# Iterate to find if any other terrain has strict higher priority
		for terrain in _active_terrains:
			if terrain.priority > best_terrain.priority:
				best_terrain = terrain

		set_current_terrain(best_terrain)

## Set current terrain
func set_current_terrain(terrain: Terrain) -> void:
	if current_terrain == terrain:
		return

	if terrain:
		var type_name = "Unknown"
		if terrain == _default_air_terrain:
			type_name = "Default Air"
		else:
			type_name = terrain.terrain_name


	var old_terrain: Terrain = current_terrain
	current_terrain = terrain

	if old_terrain:
		terrain_exited.emit(old_terrain)

	if terrain:
		terrain_entered.emit(terrain)

## Take damage
func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	if current_health == 0:
		die()

## Heal
func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)

# === VIRTUAL METHODS (Override in child classes) ===

## Custom setup logic - override in child classes
func _setup_character() -> void:
	pass

## Custom physics processing - override in child classes
func _process_physics(delta: float) -> void:
	pass

## Called when an interaction is detected
func _on_interaction_detected(interaction: Interaction) -> void:
	pass

## Called when an interaction is lost
func _on_interaction_lost(interaction: Interaction) -> void:
	pass

## Called when character dies
func die() -> void:
	set_physics_process(false) # FIX
	queue_free()

# === PRIVATE METHODS ===

## Apply the skin resource to the BodySkin node
func _apply_skin() -> void:
	if skin and skin_resource and skin_resource.texture:
		skin.set_texture(skin_resource.texture)

## Setup default air terrain for energy loss
func _setup_default_air_terrain() -> void:
	_default_air_terrain = AirTerrain.new()
	_default_air_terrain.air_resistance = 0.99  # 1% loss per second
	add_child(_default_air_terrain)
	current_terrain = _default_air_terrain

## Setup all features in the Features container
## Note: Features with auto_register=true will register themselves in their _ready()
## This method is kept for backward compatibility with features that don't auto-register
func _setup_features() -> void:
	if not features_container:
		return

	for child in features_container.get_children():
		if child is Feature:
			# Check if feature is already registered (via auto_register)
			if child not in _features:
				add_feature(child)

## Connect to all interactions in the scene
func _connect_to_interactions() -> void:
	# Find all Interaction nodes in the current scene
	var interactions: Array[Node] = get_tree().get_nodes_in_group("interactions")

	# If no group, try finding all Area2D that are Interactions
	if interactions.is_empty():
		_find_interactions_recursive(get_tree().root)
	else:
		for interaction in interactions:
			if interaction is Interaction:
				_connect_interaction(interaction)

func _find_interactions_recursive(node: Node) -> void:
	if node is Interaction and node != self:
		_connect_interaction(node)

	for child in node.get_children():
		_find_interactions_recursive(child)

func _connect_interaction(interaction: Interaction) -> void:
	if not interaction.character_in_range.is_connected(_on_interaction_entered):
		interaction.character_in_range.connect(_on_interaction_entered)
	if not interaction.character_out_of_range.is_connected(_on_interaction_exited):
		interaction.character_out_of_range.connect(_on_interaction_exited)

## Signal callback when interaction is entered
func _on_interaction_entered(character: CharacterBody2D, interaction: Interaction) -> void:
	if character == self:
		add_nearby_interaction(interaction)

## Signal callback when interaction is exited
func _on_interaction_exited(character: CharacterBody2D, interaction: Interaction) -> void:
	if character == self:
		remove_nearby_interaction(interaction)

## Calculate gravity with feature modifications
func _calculate_gravity(delta: float) -> float:
	var applied_gravity: float = gravity

	# Apply gravity multipliers from all active features
	for feature in _features:
		if feature.is_active():
			applied_gravity *= feature.get_gravity_multiplier()

	return applied_gravity * delta

## Calculate combined movement factor from all PhysicsChangers
## This is the core of the architecture!
func _calculate_all_movement_factors(delta: float) -> Vector2:
	var total_factor: Vector2 = Vector2.ZERO

	# Iterate over all features
	for feature in _features:
		if feature.is_active():
			total_factor += feature.get_movement_factor(delta, global_position)

	# Add terrain effect if in terrain
	if current_terrain:
		total_factor += current_terrain.get_movement_factor(delta, global_position)

	return total_factor

## Get the currently active grappling feature
func _get_active_grappling() -> Feature:
	for feature in _features:
		if feature is GrapplingFeature and feature.is_active():
			return feature
	return null

## Virtual method to get the local offset for grappling (can be overridden)
func get_grapple_offset() -> Vector2:
	return Vector2.ZERO

## Apply rope constraint when grappling (prevents going beyond rope length)
func _apply_grapple_constraint(delta: float) -> void:
	# Don't apply constraint during animation
	if _grapple_animation_time > 0.0:
		return

	# Find active grappling feature
	var grappling: Feature = null
	for feature in _features:
		if feature is GrapplingFeature and feature.is_active():
			grappling = feature
			break

	if not grappling:
		return

	var grapple_point: Vector2 = grappling.get_target()
	if grapple_point == Vector2.ZERO:
		return

	# Only apply constraint after initial pull
	if not grappling._has_reached_rope_length:
		return

	# Calculate offset-adjusted position
	var offset: Vector2 = get_grapple_offset()
	var pivot_global_position: Vector2 = global_position + offset

	# Check if beyond rope length
	var to_grapple: Vector2 = grapple_point - pivot_global_position
	var distance: float = to_grapple.length()

	var direction: Vector2 = to_grapple.normalized()

	# Smoothly constrain position towards rope_length
	if distance > grappling.rope_length:
		var target_position = grapple_point - direction * grappling.rope_length - offset
		# Interpolate position smoothly
		global_position = global_position.lerp(target_position, 10.0 * delta)  # Adjust 10.0 for speed

	# ANGLE LIMIT & PENDULUM PHYSICS
	var char_rel: Vector2 = (global_position + offset) - grapple_point
	if grappling.max_swing_angle_deg <= 0.0:
		# Lock directly below and remove velocity to prevent swinging
		global_position = grapple_point + Vector2.DOWN * grappling.rope_length - offset
		velocity = Vector2.ZERO
		_is_grapple_initialized = false
		return

	# Compute radial and tangential directions
	var radial_dir: Vector2 = char_rel.normalized()
	var tangential_unit: Vector2 = Vector2(-radial_dir.y, radial_dir.x) # perpendicular (CCW)
	var signed_angle: float = Vector2.DOWN.angle_to(radial_dir) # signed
	var abs_angle_deg: float = abs(rad_to_deg(signed_angle))

	# INITIAL BIAS: Subtiler CCW-Startimpuls, falls Feature es wünscht (natürlich skaliert)
	if not _is_grapple_initialized:
		if grappling and grappling.prefer_ccw_on_start:
			var desired_impulse: float = grappling.ccw_start_impulse
			# Scale down if CCW would move backward (tangential_unit.x negative)
			var scale: float = 1.0 if tangential_unit.x >= 0.0 else 0.45
			var current_tangential: float = velocity.dot(tangential_unit)
			# Only apply if current tangential movement is small to remain natural
			if abs(current_tangential) < desired_impulse * 0.5:
				velocity += tangential_unit * (desired_impulse * scale)
		# Mark initialized so we don't reapply
		_is_grapple_initialized = true

# If beyond allowed angle, reverse tangential velocity (no hard position clamping)
	# Limit Enforced: Prevent 360 degree spins.
	if abs_angle_deg > grappling.max_swing_angle_deg:
		# Tangential speed along the rope
		var tangential_speed: float = velocity.dot(tangential_unit)

		# If moving OUTWARDS (away from center center), kill velocity to stop exactly at limit
		if tangential_speed * sign(signed_angle) > 0.0:
			tangential_speed = 0.0

		# Apply restricted velocity
		var radial_component: Vector2 = radial_dir * velocity.dot(radial_dir)
		velocity = radial_component + tangential_unit * tangential_speed


	# Pendulum restoring acceleration (linear tangential): a_t = -gravity * sin(theta)
	var sin_theta: float = sin(signed_angle)
	var a_t: float = -_swing_gravity * sin_theta
	velocity += tangential_unit * (a_t * delta)

	# Project out any radial component introduced by numerical integration to keep rod length
	var radial_speed: float = velocity.dot(radial_dir)
	velocity -= radial_dir * radial_speed

	# Progressive Braking: Manually reduce speed as we approach the limit to ensure "realistic" slowing down.
	# User requirement: "Slowest at edges, fastest at bottom".
	var limit_angle: float = grappling.max_swing_angle_deg
	if limit_angle > 0:
		var angle_ratio: float = abs_angle_deg / limit_angle

		# Check if moving OUTWARDS (towards the limit)
		if velocity.dot(tangential_unit) * sign(signed_angle) > 0.0:
			# Apply braking starting from 30% of the swing (early onset)
			if angle_ratio > 0.3:
				# Strength goes from 0.0 to 1.0 (squared for exponential feel)
				var t: float = (angle_ratio - 0.3) / 0.7
				var brake_strength: float = t * t

				# Aggressive reduction:
				# At 30% angle: multiplier 1.0 (no braking)
				# At 100% angle: multiplier 0.85 (15% speed loss PER FRAME)
				# This guarantees a stop.
				var brake_factor: float = lerp(1.0, 0.85, brake_strength)
				velocity *= brake_factor

	# GLOBAL AIR RESISTANCE (Always active to prevent infinite energy)
	velocity *= 0.998

	# INITIAL IMPULSE: removed for natural swinging
	# The pendulum physics will naturally start the swing
	_is_grapple_initialized = true
