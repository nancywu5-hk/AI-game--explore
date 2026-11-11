class_name KillZone
extends Area2D

var _player: Node2D = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

	monitoring = true
	monitorable = false
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	# Follow player horizontally to stay active underneath
	# Using _physics_process to ensure it's synced with collision checks
	global_position.x = _player.global_position.x

func _on_body_entered(body: Node2D) -> void:
	if body is BaseCharacter:
		# Fish live in the water (kill zone), so they don't die there
		if body is Fish:
			return

		# Don't play death sound for enemies or tutorial ghosts
		if body.is_in_group("player"):
			AudioManager.play_sound(AudioManager.WOOL.DIE)

		body.die()
