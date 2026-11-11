## GrapplingFeature - Implements swinging on nearby nails
##
## This feature allows the character to swing on nails like a rope/pendulum.
## Activates when a Nail is in nearby_interactions and input is pressed.
## Implements rope constraint physics for realistic swinging.
class_name GrapplingFeature
extends Feature

# === SIGNALS ===
signal grapple_started(target: Vector2)
signal grapple_ended()

# === PUBLIC VARIABLES ===
var fixed_rope_length: float
var rope_length: float
var max_boost_force: float
var max_swing_speed_for_boost: float
var tension_strength: float
var swing_pump_force: float
var damping: float
var initial_pull_strength: float
var max_swing_angle_deg: float = 90.0

# Edge boost when hitting swing extremes: helps natural back-swinging when too slow
var edge_boost_multiplier: float = 1.5
var edge_min_tangential_speed: float = 120.0

# Prefer CCW start behaviour
var prefer_ccw_on_start: bool = true
var ccw_start_impulse: float = 180.0

# === PRIVATE VARIABLES ===
var _grapple_target: Vector2 = Vector2.ZERO
var _target_nail: Interaction = null
var _has_reached_rope_length: bool = false  # Track if we've reached the rope length once
var _input_buffer_timer: float = 0.0
var _animated_rope_length: float = 0.0  # Current animated rope length for smooth transition
var _rope_animation_speed: float = 800.0  # Speed of rope length animation in pixels per second
var _release_without_boost: bool = false  # Flag to prevent boost when releasing due to falling nail
const GRAPPLE_TOLERANCE: float = 20.0 # Extra pixels to allow grappling (compensates for character width)

# === BUILT-IN METHODS ===
func _ready() -> void:
	super._ready()
	feature_name = "Grappling"
	setup_tweakables_generic({
		"swing_pump_force": "swing_pump_force",
		"max_boost_force": "max_boost_force",
		"fixed_rope_length": "fixed_rope_length",
		"max_swing_angle": "max_swing_angle_deg",
		"edge_boost_multiplier": "edge_boost_multiplier",
		"edge_min_tangential_speed": "edge_min_tangential_speed",
		"prefer_ccw_on_start": "prefer_ccw_on_start",
		"ccw_start_impulse": "ccw_start_impulse"
	})

	# Set internal defaults for parameters removed from the UI
	max_swing_speed_for_boost = 800.0
	tension_strength = 2500.0
	damping = 0.995
	initial_pull_strength = 1500.0

func _physics_process(delta: float) -> void:
	# Check if the target nail is falling (for rusty nails)
	if is_active() and is_instance_valid(_target_nail) and _target_nail is RustyNail and (_target_nail as RustyNail)._is_falling:
		_release_without_boost = true
		release()
		return

	# Animation is now handled in BaseCharacter
	pass

	# Input Buffering: Retry grapple if button was pressed recently
	if _input_buffer_timer > 0.0:
		_input_buffer_timer -= delta
		if _input_buffer_timer > 0.0 and not is_active():
			var character = get_character()
			if character:
				_try_start_grapple(character)

# === PUBLIC METHODS ===

## Set the grapple target position (called by character)
func set_target(target_position: Vector2, nail: Interaction = null) -> void:
	_input_buffer_timer = 0.0 # Reset buffer on success
	_grapple_target = target_position
	_target_nail = nail
	_has_reached_rope_length = false  # Start animation

	# Set rope length immediately to final value
	rope_length = fixed_rope_length
	_animated_rope_length = fixed_rope_length

	if nail:
		# Only mark as used if the character is a real player
		# Shadow Wool is removed from "player" group so it won't block re-use
		if get_character() and get_character().is_in_group("player"):
			nail.set_used(true)

		if nail.has_method("trigger"):
			nail.trigger()

	activate()
	grapple_started.emit(target_position)

## Release the grapple
func release() -> void:
	if is_instance_valid(_target_nail):
		# Only unmark if we are a real player (matching set_target logic)
		if get_character() and get_character().is_in_group("player"):
			_target_nail.set_used(false)

	# Apply boost based on swing speed, but not if releasing due to falling nail
	if not _release_without_boost:
		var character: BaseCharacter = get_character()
		if character:
			var speed: float = character.velocity.length()
			var boost_factor: float = clamp(speed / max_swing_speed_for_boost, 0.0, 1.0)

			if speed > 0:
				var multi: float = 1.0
				if is_instance_valid(_target_nail) and _target_nail.has_method("get_boost_multiplier"):
					multi = _target_nail.get_boost_multiplier()

				var boost_vector: Vector2 = character.velocity.normalized() * max_boost_force * boost_factor * multi
				character.velocity += boost_vector

	# Reset the flag
	_release_without_boost = false

	_target_nail = null
	_has_reached_rope_length = false
	deactivate()
	grapple_ended.emit()

## Get current grapple target
func get_target() -> Vector2:
	return _grapple_target

## Get the nail being grappled to
func get_target_nail() -> Interaction:
	return _target_nail

# === OVERRIDDEN METHODS ===

func handle_input(character: BaseCharacter) -> void:
	pass
	# if Input.is_action_just_pressed("interact"):
	# 	# Try immediately
	# 	_try_start_grapple(character)
	#
	# 	# If not successful immediately, start buffer timer
	# 	if not is_active():
	# 		_input_buffer_timer = 0.15 # 150ms buffer
	#
	# if Input.is_action_just_released("interact"):
	# 	release()

func _try_start_grapple(character: BaseCharacter) -> void:
	var nail: BaseNail = _find_nearest_nail(character)
	if nail:
		set_target(nail.get_grapple_point(), nail)

func _find_nearest_nail(character: BaseCharacter) -> BaseNail:
	var nearest: BaseNail = null
	var nearest_distance: float = INF

	for interaction in character.nearby_interactions:
		var nail := interaction as BaseNail
		if not nail:
			continue

		# Strict distance check against detection radius with TOLERANCE
		var distance: float = character.global_position.distance_to(nail.global_position)
		var radius: float = nail.get_detection_radius()

		# Scale tolerance by character scale to support larger characters
		# This prevents rejection when a large character is touching the zone edge but their center is far out
		var scaled_tolerance: float = GRAPPLE_TOLERANCE * max(character.scale.x, character.scale.y)

		# Allow if distance is within radius + tolerance AND within fixed_rope_length
		# This handles cases where character shape overlaps nail shape but centers are far
		if (radius > 0 and distance > (radius + scaled_tolerance)) or distance > fixed_rope_length:

			continue

		if distance < nearest_distance:
			nearest = nail
			nearest_distance = distance

	return nearest

func _on_activated() -> void:
	pass

func _on_deactivated() -> void:
	_grapple_target = Vector2.ZERO
	_has_reached_rope_length = false

func _calculate_movement_factor(delta: float, character_position: Vector2) -> Vector2:
	if _grapple_target == Vector2.ZERO:
		return Vector2.ZERO

	# Vector from character to grapple point
	var to_grapple: Vector2 = _grapple_target - character_position
	var distance: float = to_grapple.length()

	# No initial pull force - we rely on BaseCharacter constraint

	# After initial pull: NO FORCE - constraint is handled in BaseCharacter
	return Vector2.ZERO
