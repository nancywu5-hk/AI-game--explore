## Terrain - Abstract Base Class
##
## Base class for all terrain types (underwater, ice, mud, etc.)
## Terrains modify character physics based on environmental conditions.
##
## Terrains inherit from PhysicsChanger and affect characters within their area.
## Example: Underwater terrain slows down movement, ice terrain reduces friction.
class_name Terrain
extends PhysicsChanger

# === SIGNALS ===
signal character_entered(character: CharacterBody2D)
signal character_exited(character: CharacterBody2D)

# === EXPORTED VARIABLES ===
@export var terrain_name: String = "UnnamedTerrain"
@export var affects_movement: bool = true
@export var uses_standard_gravity: bool = true # If false, BaseCharacter won't apply standard gravity
@export var can_glide_upwards: bool = false # If true, allows gliding even when moving upwards (e.g. updrafts)
@export var priority: int = 0 # Higher priority terrains override lower ones (e.g. Water > Generic Zone)

# === PRIVATE VARIABLES ===
var _characters_in_terrain: Array[CharacterBody2D] = []
var _pending_characters: Array[CharacterBody2D] = []

# === PUBLIC VARIABLES ===
var detection_area: Area2D

# === BUILT-IN METHODS ===
func _ready() -> void:
	detection_area = _find_detection_area()

	# Support for adding CollisionShapes directly to the Terrain node in the editor.
	# We move them into the DetectionArea at runtime so they trigger the physics logic.
	if detection_area:
		# Force collision mask to include Layer 1 (Default) and Layer 2 (Player) explicitly
		# This ensures we catch characters even if they are on default layer
		var mask = detection_area.collision_mask
		if mask & 1 == 0:
			detection_area.collision_mask |= 1 # Add Layer 1
		if mask & 2 == 0:
			detection_area.collision_mask |= 2 # Add Layer 2



		_move_collision_shapes_to_area()

		# DEBUG: Verify we have shapes
		var shape_count = 0
		for child in detection_area.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				shape_count += 1


		# Ensure monitoring is on!
		detection_area.monitoring = true
		detection_area.monitorable = true # Being monitorable helps debug, though not strictly needed for detection

		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)

		# SAFETY CHECK: Wait one frame, then manually check for bodies already inside.
		# This fixes issues where spawning inside an Area2D doesn't trigger the signal immediately.
		get_tree().process_frame.connect(_check_initial_overlaps, CONNECT_ONE_SHOT)
	else:
		push_warning("Terrain '%s' has no DetectionArea child node!" % terrain_name)

func _check_initial_overlaps() -> void:
	if not detection_area: return

	# Manually force update to catch bodies
	# Sometimes Area2D needs a frame to update overlapping bodies
	var bodies = detection_area.get_overlapping_bodies()


	for body in bodies:
		_on_body_entered(body)

func _physics_process(delta: float) -> void:
	# Check pending characters
	for i in range(_pending_characters.size() - 1, -1, -1):
		var char = _pending_characters[i]
		if _should_character_enter(char):
			_pending_characters.remove_at(i)
			_add_character_to_terrain(char)

	# Check active characters - remove if they drift out of condition (e.g. surfacing)
	for i in range(_characters_in_terrain.size() - 1, -1, -1):
		var char = _characters_in_terrain[i]
		if not _should_character_enter(char):
			_characters_in_terrain.remove_at(i)
			_remove_character_from_terrain_logic(char)
			# Move back to pending, so if they go deep again, they re-enter
			if char not in _pending_characters:
				_pending_characters.append(char)

	# Standard physics processing is sufficient.
	# We rely on Area2D 'body_entered' and 'body_exited' signals.
	pass

func _move_collision_shapes_to_area() -> void:
	# Iterate backwards to safely remove children while iterating
	var children = get_children()
	for i in range(children.size() - 1, -1, -1):
		var child = children[i]
		if child is CollisionShape2D or child is CollisionPolygon2D:
			# Cache global transform before reparenting
			var global_trans = child.global_transform

			remove_child(child)
			detection_area.add_child(child)

			# Restore global transform to ensure it stays exactly where placed in editor
			child.global_transform = global_trans

func _find_detection_area() -> Area2D:
	if has_node("DetectionArea"):
		return $DetectionArea

	for child in get_children():
		if child is Area2D:
			return child

	return null

# === PUBLIC METHODS ===

## Check if a specific character is in this terrain
func is_character_in_terrain(character: CharacterBody2D) -> bool:
	return character in _characters_in_terrain

## Get all characters currently in this terrain
func get_characters_in_terrain() -> Array[CharacterBody2D]:
	return _characters_in_terrain.duplicate()

# === VIRTUAL METHODS (Override in child classes) ===

## Get movement factor - MUST be overridden
## @param delta: The physics delta time
## @param character_position: The current position of the character
## @return Vector2: The movement factor to apply (can be negative to slow down)
func get_movement_factor(delta: float, character_position: Vector2) -> Vector2:
	if not affects_movement:
		return Vector2.ZERO

	return _calculate_terrain_effect(delta, character_position)

## Override this in child classes to implement terrain-specific physics
func _calculate_terrain_effect(_delta: float, _character_position: Vector2) -> Vector2:
	push_error("Terrain._calculate_terrain_effect() must be overridden in: " + terrain_name)
	return Vector2.ZERO

## Get damping factor for energy loss (override in child classes)
## @return float: Damping multiplier (0.99 = 1% loss per second, 1.0 = no damping)
func get_damping_factor() -> float:
	return 1.0  # No damping by default

## Apply terrain-specific damping to a character (override in child classes)
## @param character: The character to apply damping to
## @param delta: The physics delta time
func apply_damping(character: CharacterBody2D, delta: float) -> void:
	var damping_factor: float = get_damping_factor()
	if damping_factor < 1.0:
		# Apply damping: velocity = velocity * damping^(delta * 60)
		# This creates exponential decay (realistic energy loss)
		var damping_per_frame: float = pow(damping_factor, delta * 60.0)
		character.velocity *= damping_per_frame

## Called when a character enters this terrain
func _on_character_entered(character: CharacterBody2D) -> void:
	pass

## Called when a character exits this terrain
func _on_character_exited(character: CharacterBody2D) -> void:
	pass

## Check if a character should strictly enter this terrain.
## Useful for delaying entry until character is submerged or specific condition is met.
func _should_character_enter(character: CharacterBody2D) -> bool:
	return true

func _add_character_to_terrain(body: CharacterBody2D) -> void:
	_characters_in_terrain.append(body)
	_on_character_entered(body)
	character_entered.emit(body)

	if body.has_method("enter_terrain"):
		body.enter_terrain(self)

func _remove_character_from_terrain_logic(body: CharacterBody2D) -> void:
	_on_character_exited(body)
	character_exited.emit(body)

	if body.has_method("exit_terrain"):
		body.exit_terrain(self)

# === SIGNAL CALLBACKS ===
func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		# Prevent duplicates (important if we manually check overlaps AND get a signal)
		if body in _characters_in_terrain or body in _pending_characters:
			return

		if _should_character_enter(body):
			_add_character_to_terrain(body)
		else:
			_pending_characters.append(body)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		if body in _pending_characters:
			_pending_characters.erase(body)
			return

		_characters_in_terrain.erase(body)
		_remove_character_from_terrain_logic(body)
