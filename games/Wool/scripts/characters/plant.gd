class_name Plant
extends BaseEnemy

@export var fireball_scene: PackedScene

var _fireball_speed: float = 300.0

var _audio_player: AudioStreamPlayer
var _animated_sprite: AnimatedSprite2D
var _anim_sequence: Array[String] = ["1", "2", "3"]
var _current_anim_index: int = 0

func _ready() -> void:
	super._ready()
	_setup_audio()
	_setup_animations()

func _setup_audio() -> void:
	if not _audio_player:
		_audio_player = AudioManager.create_audio_player(AudioManager.ENEMIES.SPUCKI, self)
		if _audio_player:
			# VOLUME SET globally in AudioManager now (10%)
			despawn_requested.connect(_on_despawn_requested)

func _setup_animations() -> void:
	_animated_sprite = $Skin/AnimatedSprite2D
	if _animated_sprite:
		_animated_sprite.animation_finished.connect(_on_animation_finished)
		_current_anim_index = 0
		_animated_sprite.play(_anim_sequence[0])

func _on_animation_finished() -> void:
	if not _animated_sprite:
		return

	# After each animation finishes, spit and move to the next animation
	shoot_fireball()
	_current_anim_index = (_current_anim_index + 1) % _anim_sequence.size()
	_animated_sprite.play(_anim_sequence[_current_anim_index])

func _on_despawn_requested(_node: Node) -> void:
	if _audio_player:
		_audio_player.stop()

func _on_game_state_changed(new_state: int) -> void:
	super._on_game_state_changed(new_state)
	if new_state == GameManager.GameState.GAME_OVER:
		if _audio_player:
			_audio_player.stop()

func shoot_fireball() -> void:
	if not fireball_scene:
		push_warning("Plant: No fireball_scene assigned!")
		return

	# Play spucki sound
	if _audio_player:
		_audio_player.play()

	var fireball = fireball_scene.instantiate()
	get_parent().add_child(fireball)

	var spawn_pos_local = Vector2(0, -250)
	fireball.global_position = to_global(spawn_pos_local)

	if "speed" in fireball:
		fireball.speed = _fireball_speed

	if "direction" in fireball:
		fireball.direction = Vector2.UP.rotated(global_rotation)

func _process_ai(_delta: float) -> void:
	velocity.x = 0
	velocity.y = 0
