class_name ShadowWool
extends Wool

var _sim_jump_pressed: bool = false
var _sim_jump_held: bool = false

func _ready() -> void:
	# Do NOT call super._ready() immediately if we want to modify things before?
	# Actually super._ready() does setup. We want that.
	super._ready()

	# Remove from 'player' group to avoid interference
	if is_in_group("player"):
		remove_from_group("player")

	# Disable Camera
	if camera:
		camera.enabled = false
		camera.queue_free()

	# Collision Layer Adjustment
	# We want to collide with World (Layer 1) and Nails (Interaction?)
	# But NOT Enemies (Layer ?)
	# Standard: 1=World, 2=Character, 3=Enemy
	# We keep Layer 2 so Nails can detect us.
	# We Mask Layer 1 so we stand on ground.
	collision_mask = 1

	# Initial State
	velocity = Vector2.ZERO
	_game_started = true # Force game start mode so it runs physics logic

func _unhandled_input(event: InputEvent) -> void:
	pass # Ignore real input

func _get_jump_just_pressed() -> bool:
	var res = _sim_jump_pressed
	_sim_jump_pressed = false
	return res

func _get_jump_held() -> bool:
	return _sim_jump_held

func _handle_input() -> void:
	# Override Wool's auto-run logic.
	# We want ShadowWool to stay in place horizontally (unless it has momentum from player),
	# but perform the vertical actions (Jump/Grapple).

	_direction = 0.0 # Prevent auto-run

	var input_just_pressed: bool = _get_jump_just_pressed()
	var input_pressed: bool = _get_jump_held()

	# 1. Ground Logic: Jump Only
	if is_on_floor():
		if input_just_pressed:
			_jump()
			# Simulate running jump momentum
			velocity.x = move_speed

	# 2. Air Logic: Grapple & Forward Movement
	else:
		# Move forward while in air
		_direction = 1.0

		var is_grappling: bool = grappling_feature and grappling_feature.is_active()

		if input_pressed:
			# HOLDING
			if not is_grappling:
				var best_nail: Interaction = _find_best_grapple_target()
				if best_nail:
					# Reset held latch on grapple start
					grappling_feature.set_target(best_nail.get_grapple_point(), best_nail)
				else:
					# No nails nearby, but trying to grapple - increase gravity
					_extra_gravity = gravity * 2.0
			else:
				_extra_gravity = 0.0
		else:
			# RELEASED
			if is_grappling:
				grappling_feature.release()

			_extra_gravity = 0.0

	_vertical_direction = 0.0

# === CONTROLS ===
func sim_press_jump() -> void:
	_sim_jump_pressed = true
	_sim_jump_held = true

func sim_release_jump() -> void:
	_sim_jump_held = false

func die() -> void:
	# Prevent Game Over
	# Just vanish or reset?
	# Tutorial controller handles reset loop.
	pass

func _update_nail_highlight() -> void:
	# Disable highlighting for Shadow Wool
	pass

func _should_track_as_player() -> bool:
	return false

func _on_grapple_started(target: Vector2) -> void:
	# Override BaseCharacter to MUTE SOUND
	_is_grapple_initialized = false
	_grapple_animation_time = 0.1
	_grapple_target_position = target
	# AudioManager.play_sound(AudioManager.WOOL.HOOK) # MUTED

func _on_grapple_ended() -> void:
	# Override BaseCharacter to MUTE SOUND
	# if _is_grapple_initialized:
	# 	AudioManager.play_sound(AudioManager.WOOL.SCHWINGEN) # MUTED
	_is_grapple_initialized = false
