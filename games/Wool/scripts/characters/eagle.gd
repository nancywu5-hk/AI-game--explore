class_name Eagle
extends BaseEnemy



var _audio_player: AudioStreamPlayer

func _ready() -> void:
	super._ready()
	_setup_audio()

func reset() -> void:
	super.reset()
	velocity.x = -fly_speed
	velocity.y = 0.0
	_spawn_y = global_position.y # Capture new spawn height on reuse
	_update_direction()
	_start_audio()

func _setup_audio() -> void:
	if not _audio_player:
		_audio_player = AudioManager.create_audio_player(AudioManager.ENEMIES.BIRD, self)
		if _audio_player:
			# VOLUME SET globally in AudioManager now (10%)
			_audio_player.finished.connect(_on_audio_finished)
			despawn_requested.connect(_on_despawn_requested)
			_start_audio()

func _start_audio() -> void:
	if _audio_player and not _audio_player.playing:
		_audio_player.play()

func _on_audio_finished() -> void:
	if _audio_player and is_inside_tree():
		_audio_player.play()

func _on_despawn_requested(_node: Node) -> void:
	if _audio_player:
		_audio_player.stop()

func _on_game_state_changed(new_state: int) -> void:
	super._on_game_state_changed(new_state)
	if new_state == GameManager.GameState.GAME_OVER:
		if _audio_player:
			_audio_player.stop()

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

	# Only connect exit signal after we have entered the screen at least once.
	# This prevents immediate despawn since we spawn off-screen to the right.
	notifier.screen_entered.connect(func():
		# Increase volume when entering screen
		if _audio_player:
			var tween = create_tween()
			tween.tween_property(_audio_player, "volume_db", linear_to_db(0.5), 0.5)

		# Once we enter the screen, we care about exiting it
		if not notifier.screen_exited.is_connected(_on_screen_exited):
			notifier.screen_exited.connect(_on_screen_exited)
	)

@export var hover_speed: float = 150.0
@export var fly_speed: float = 300.0

var _sprite_ref: AnimatedSprite2D = null
var _spawn_y: float = 0.0

func _process_ai(delta: float) -> void:
	# Maintain leftward velocity directly (for X)
	velocity.x = -fly_speed

	# Find sprite if missing
	if not _sprite_ref:
		if skin and skin.has_node("AnimatedSprite2D"):
			_sprite_ref = skin.get_node("AnimatedSprite2D")
			if _sprite_ref and _sprite_ref.sprite_frames:
				# Force 25 FPS
				_sprite_ref.sprite_frames.set_animation_speed(_sprite_ref.animation, 25.0)

	# Frame-based movement logic (Position Offset)
	# We override velocity.y purely for effect or use direct position modification
	# But BaseCharacter uses move_and_slide based on velocity.
	# To stay perfectly vertically centered, we should calculate the velocity needed
	# to reach the target offset for the current frame.

	var target_offset: float = 0.0

	if _sprite_ref:
		var frame = _sprite_ref.frame
		# 1-Down (frame 0) -> 2-Up (frame 1) -> 3-Down (frame 2)
		# Let's map frames to offsets relative to spawn_y
		# Frame 1 (Up) -> Higher position (-10)
		# Frame 0, 2 (Down) -> Lower position (+10)
		if frame == 1:
			target_offset = -100.0
		else:
			target_offset = 100.0

	# Calculate target Y
	var target_y = _spawn_y + target_offset

	# Calculate velocity needed to reach target_y in this frame (snap to position)
	# v = d / t -> (target_y - current_y) / delta
	# We simply set velocity.y to move towards target.
	# Or better: smooth interp? User wants "jerk" synced to frame.
	# Snapping via velocity might be unstable with physics.

	# Hybrid: Use standard move_and_slide for X, but manual Y correction?
	# Let's try high-speed velocity approach.
	var diff = target_y - global_position.y
	var desired_vy = diff * 15.0

	# Smoothly interpolate velocity to avoid "jumping"
	# Use lerp for organic easing (simulates inertia)
	velocity.y = lerp(velocity.y, desired_vy, delta * 3.0)

	# Direct snap check: if very close, just set it? No, physics engine hates that.
	# Let's try just setting velocity based on direction to target.
	# If we are effectively "hovering", we just want to wobble around _spawn_y.

	_update_direction()

# Audio handled by BaseEnemy

func _update_direction() -> void:
	# Always face left (direction of movement)
	if skin:
		# If velocity is negative (left), scale.x should be negative?
		# It depends on the sprite. Usually positive scale = right facing.
		# If we fly left, we want to face left.
		# Assuming original sprite faces right.
		if skin.scale.x > 0:
			skin.scale.x = -abs(skin.scale.x)

func _on_screen_exited() -> void:
	# Decrease volume when exiting screen
	if _audio_player:
		var tween = create_tween()
		tween.tween_property(_audio_player, "volume_db", linear_to_db(0.25), 0.5)
