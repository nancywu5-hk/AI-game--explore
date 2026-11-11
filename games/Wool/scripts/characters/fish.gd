class_name Fish
extends BaseEnemy

# Removed export var jump_strength
# Jump strength is now calculated dynamically

@export var horizontal_speed: float = -900.0

var _start_y: float = 0.0
var _start_x: float = 0.0

var _start_player: AudioStreamPlayer
# _end_player removed (using global AudioManager.play_sound)
var _falling_sound_played: bool = false

func _ready() -> void:
	super._ready()
	_start_y = global_position.y
	_start_x = global_position.x

	_jump()
	_setup_visibility_notifier()
	_setup_audio()

func reset() -> void:
	super.reset()
	_start_y = global_position.y
	_start_x = global_position.x
	# Reset falling sound flag on reset
	_falling_sound_played = false
	_jump()
	# _start_audio() removed, handled in jump

func _setup_audio() -> void:
	if not _start_player:
		_start_player = AudioManager.create_audio_player(AudioManager.ENEMIES.FISH_START, self)
		if _start_player:
			despawn_requested.connect(_on_despawn_requested)

	# _end_player removed

func _play_start_sound() -> void:
	if _start_player:
		_start_player.play()

func _play_end_sound() -> void:
	AudioManager.play_sound(AudioManager.ENEMIES.FISH_END)

# _on_audio_finished removed as we don't loop

func _on_despawn_requested(_node: Node) -> void:
	if _start_player: _start_player.stop()

func _on_game_state_changed(new_state: int) -> void:
	super._on_game_state_changed(new_state)
	if new_state == GameManager.GameState.GAME_OVER:
		if _start_player: _start_player.stop()

func _setup_visibility_notifier() -> void:
	var notifier = VisibleOnScreenNotifier2D.new()

	# Dynamically calculate rect from sprite
	var rect = Rect2(-50, -50, 100, 100) # Fallback

	if skin and skin.has_node("AnimatedSprite2D"):
		var sprite = skin.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if sprite:
			var frames = sprite.sprite_frames
			if frames and frames.has_animation(sprite.animation):
				var texture = frames.get_frame_texture(sprite.animation, 0)
				if texture:
					var size = texture.get_size()
					rect = Rect2(-size / 2.0, size)

	notifier.rect = rect
	add_child(notifier)

func _process_ai(delta: float) -> void:
	# BaseCharacter applies gravity in _process_physics.
	# We just need to check if we fell back to water level.

	if velocity.y > 0 and global_position.y >= _start_y:
		# Fish has returned to the water -> Despawn
		despawn_requested.emit(self)
		set_physics_process(false)
		return

	# Play falling sound if moving down and hasn't played yet
	if velocity.y > 0:
		if not _falling_sound_played:
			_falling_sound_played = true
			_play_end_sound()

	# Rotate based on velocity to face movement direction
	rotation = velocity.angle() + PI

func _jump() -> void:
	# Recalculate or reuse jump velocity
	# Target above the playable area, scaled to viewport
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var target_y: float = GameManager.PLAYABLE_HEIGHT_TOP - viewport_height
	var height_diff = _start_y - target_y

	if height_diff > 0:
		var jump_velocity = sqrt(2.0 * gravity * height_diff)
		velocity.y = -jump_velocity
		velocity.x = horizontal_speed # Apply lateral movement

		# Reset falling sound flag for new jump (if reused)
		_falling_sound_played = false
		_play_start_sound()
	else:
		velocity.y = -1000.0
		velocity.x = horizontal_speed
