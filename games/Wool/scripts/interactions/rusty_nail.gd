class_name RustyNail
extends BaseNail

## Emitted once the nail has finished falling and is ready to be recycled.
## The nail must NOT free itself: it belongs to LevelGenerator's pool, and
## freeing it stranded the pool's reference to it - the pool then rebuilt a
## fresh instance for every rusty nail after the first ten.
signal despawn_requested(nail: Node2D)

@export var fall_delay: float = 3.0
@export var min_fall_delay: float = 1.5
@export var step_size: float = 2000.0 # Distance interval for difficulty increase
@export var decay_percent: float = -0.1 # Decrease per step (negative)

var _is_triggered: bool = false
var _is_falling: bool = false
var _fall_timer: Timer
var _shake_tween: Tween

func _ready() -> void:
	super._ready()
	_setup_timer()

## Undo everything a fall leaves behind, so a recycled nail spawns intact.
## Previously this nail freed itself instead of returning to the pool, so this
## state never had to be unwound - now it does.
func reset() -> void:
	super.reset()

	_is_triggered = false
	_is_falling = false
	_was_used = false
	_fall_time = 0.0
	_current_active_delay = fall_delay

	if _shake_tween:
		_shake_tween.kill()
		_shake_tween = null

	if _fall_timer:
		_fall_timer.stop()

	# Restore the intact sprites and hide the broken-off ones.
	for node_name in [NODE_FRONT_SPRITE, NODE_BACK_SPRITE, NODE_SHADOW_SPRITE, "front", "back"]:
		var node = get_node_or_null(node_name)
		if node:
			node.visible = true

	var falloff = get_node_or_null("FalloffSprite")
	if falloff:
		falloff.visible = false
	if _falloff_shadow:
		_falloff_shadow.visible = false

	_update_visual()

func _setup_interaction() -> void:
	interaction_name = "RustyNail"
	# Rusty colors (usually fixed texture, but can tint)
	normal_color = InteractionConstants.get_value("Visuals", "rusty_nail_color", InteractionConstants.DEFAULT_RUSTY_NAIL_COLOR)
	highlight_color = InteractionConstants.get_value("Visuals", "highlight_nail_color", InteractionConstants.DEFAULT_HIGHLIGHT_COLOR)
	_update_visual()

func _setup_timer() -> void:
	_fall_timer = Timer.new()
	_fall_timer.one_shot = true
	_fall_timer.wait_time = fall_delay
	_fall_timer.timeout.connect(_on_fall_timeout)
	add_child(_fall_timer)

# Triggered when player grapples
func trigger() -> void:
	if _is_triggered: return
	_is_triggered = true

	# Start Shake Effect
	_start_shake()

	# Calculate dynamic delay based on distance using ScaleUtils
	var current_distance_px = GameManager.get_current_distance() * 10.0 # Convert meters back to pixels?
	# Actually GameManager.get_current_distance() returns meters (int).
	# ScaleUtils usually works on pixels or units. LevelGenerator uses X position (pixels).
	# Let's use player global x position if possible, else use distance * 10.
	# But wait, RustyNail is at a specific position. We should use ITS position!
	var nail_x = global_position.x
	# The distance traveled is roughly nail_x (since start is 0).

	var steps = ScaleUtils.steps_from_position(nail_x, step_size)
	var scaler = ScaleUtils.scaled_value(fall_delay, decay_percent, steps)
	var current_delay = max(scaler, min_fall_delay)

	# Emit signal using GameManager
	GameManager.rusty_nail_timer_started.emit(current_delay)

	_fall_timer.wait_time = current_delay
	_fall_timer.start()

	_current_active_delay = current_delay

var _current_active_delay: float = 3.0

var _was_used: bool = false
var _falloff_shadow: Sprite2D

# Falling Variables
var _fall_speed: float = 300.0
var _wobble_freq: float = 5.0
var _wobble_mag: float = 20.0
var _fall_time: float = 0.0
var _fall_start_x: float = 0.0
var _rotation_mag: float = 0.5 # Max tilt in radians

func _process(delta: float) -> void:
	if _is_triggered and not _is_falling:
		var used = is_being_used()
		if used:
			var time_left = _fall_timer.time_left
			var progress = 1.0 - (time_left / _current_active_delay)
			GameManager.rusty_nail_timer_updated.emit(progress)
		elif _was_used and not used:
			GameManager.rusty_nail_timer_stopped.emit()
		_was_used = used

	# Falling Logic
	if _is_falling:
		_fall_time += delta

		# Vertical Movement
		position.y += _fall_speed * delta

		# Horizontal Sine Wave
		var offset_x = sin(_fall_time * _wobble_freq) * _wobble_mag
		position.x = _fall_start_x + offset_x

		# Rotation tilting back and forth
		# Using cos because it represents the horizontal velocity (derivative of sin)
		# so the tilt is maximum at the center of the swing.
		rotation = cos(_fall_time * _wobble_freq) * _rotation_mag

		# Cleanup if too far down
		if _fall_time > 3.0:
			_is_falling = false
			despawn_requested.emit(self)

func _start_shake() -> void:
	if _shake_tween: _shake_tween.kill()
	_shake_tween = create_tween()
	# Random shake offset
	_shake_tween.set_loops() # Infinite loops, killed on timeout
	_shake_tween.tween_property(self, "position", position + Vector2(5,0), 0.05)
	_shake_tween.tween_property(self, "position", position - Vector2(5,0), 0.05)
	_shake_tween.tween_property(self, "position", position, 0.05)

func _on_fall_timeout() -> void:
	# Break/Fall logic
	is_active = false
	_is_falling = true
	_fall_start_x = position.x # Store initial X for sine wave center

	# Visual Update: Toggle Sprites
	var front = get_node_or_null(NODE_FRONT_SPRITE)
	if front: front.visible = false

	var back = get_node_or_null(NODE_BACK_SPRITE)
	if back: back.visible = false

	# Try legacy nodes if standard ones fail, just in case
	if not front:
		var lf = get_node_or_null("front")
		if lf: lf.visible = false
	if not back:
		var lb = get_node_or_null("back")
		if lb: lb.visible = false

	var shadow = get_node_or_null(NODE_SHADOW_SPRITE)
	if shadow: shadow.visible = false

	var falloff = get_node_or_null("FalloffSprite")
	if falloff:
		falloff.visible = true

		# Create/Setup Shadow for Falloff
		if not _falloff_shadow:
			_falloff_shadow = Sprite2D.new()
			_falloff_shadow.texture = falloff.texture
			_falloff_shadow.modulate = Color(0, 0, 0, 0.8)
			_falloff_shadow.z_index = -2
			_falloff_shadow.position = falloff.position + Vector2(10, 10)
			_falloff_shadow.scale = falloff.scale # Sync Scale if any
			add_child(_falloff_shadow)
			# Move behind everything
			move_child(_falloff_shadow, 0)

		_falloff_shadow.visible = true

	if _shake_tween: _shake_tween.kill()

	GameManager.rusty_nail_timer_stopped.emit()


func _update_visual() -> void:
	var color = highlight_color if is_active else normal_color
	# Only tint if desired, usually rusty nail has specific texture
	# But highlighting is important

	var back = get_node_or_null(NODE_BACK_SPRITE) # e.g. "back" node name mapped to constant?
	# RustyNail scene has "back" and "front" nodes (lowercase)
	# We should rename them in the scene to match BaseNail "BackSprite", "FrontSprite"
	# OR handle both names here.

	# Let's strictly rename scene nodes.
	if back: back.modulate = color
	var front = get_node_or_null(NODE_FRONT_SPRITE)
	if front: front.modulate = color

	# Legacy Fallback
	var legacy_back = get_node_or_null("back")
	if legacy_back: legacy_back.modulate = color
	var legacy_front = get_node_or_null("front")
	if legacy_front: legacy_front.modulate = color
