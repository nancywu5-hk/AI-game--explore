extends Node2D

@export var nail_scene: PackedScene = preload("res://scenes/interactions/nail.tscn")
@export var rusty_nail_scene: PackedScene = preload("res://scenes/interactions/rusty_nail.tscn")
@export var boost_nail_scene: PackedScene = preload("res://scenes/interactions/boost_nail.tscn")

enum NailType { NORMAL, RUSTY, BOOST }

## Vertical generation range
## Vertical generation range
@export var gen_min_y: float = -1600.0 # Recalculated in _ready()
@export var gen_max_y: float = -150.0 # Recalculated in _ready()

const NAILS_PER_SEGMENT: int = 10

@onready var nails_container: Node = get_node_or_null("../Nails")

var _player: Node2D = null
var _camera_width: float = 0.0
var _last_generated_x: float = 0.0
var _last_camera_check_x: float = -1000.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
@export var minimal_nail_distance: float = 300.0
@export var step_size: float = 512.0
@export var nail_distance_increase_percent: float = 0.01
@export var max_min_nail_distance: float = 512.0
@export var rusty_nail_probability: float = 0.01
@export var rusty_nail_probability_increase_percent: float = 0.01
@export var boost_nail_probability: float = 0.1
var _nails: Array[Node2D] = []
var _normal_nail_pool: ObjectPool
var _rusty_nail_pool: ObjectPool
var _boost_nail_pool: ObjectPool

func _ready() -> void:
	# Initialize pools
	if nails_container:
		_normal_nail_pool = ObjectPool.new(nail_scene, nails_container, 20)
		_rusty_nail_pool = ObjectPool.new(rusty_nail_scene, nails_container, 10)
		_boost_nail_pool = ObjectPool.new(boost_nail_scene, nails_container, 10)
	else:
		_normal_nail_pool = ObjectPool.new(nail_scene, self, 20)
		_rusty_nail_pool = ObjectPool.new(rusty_nail_scene, self, 10)
		_boost_nail_pool = ObjectPool.new(boost_nail_scene, self, 10)

	# Recalculate generation bounds from dynamic playable height
	gen_min_y = GameManager.PLAYABLE_HEIGHT_TOP + 155.0
	gen_max_y = GameManager.PLAYABLE_HEIGHT_BOTTOM - 150.0

	# Initialize RNG with session seed from GameManager
	_rng.seed = GameManager.current_seed

	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_camera_width = get_viewport().get_visible_rect().size.x

		# Initial spawn: 0 <= x <= camera_width
		_generate_nails_in_range(1024, _camera_width)

		# Spawn next segment: camera_width <= x <= 2*camera_width
		_generate_nails_in_range(_camera_width, 2.0 * _camera_width)
		_last_generated_x = 2.0 * _camera_width

func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return

	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if not _player.camera:
		return

	var camera_left_border = _player.camera.global_position.x - (_camera_width / 2.0) / _player.camera.zoom.x

	# Optimization: Only update generation checks if camera moved significantly
	# This avoids checking arrays every single frame
	if abs(camera_left_border - _last_camera_check_x) < 100.0:
		return
	_last_camera_check_x = camera_left_border

	# Generate ahead in small chunks to distribute load
	# Instead of filling the entire 2 * camera_width buffer in one go,
	# we only generate a small slice per frame if needed.
	if _last_generated_x < camera_left_border + 2.0 * _camera_width:
		# Use a smaller chunk size (e.g. 512px) to avoid lag spikes
		var chunk_size = 512.0
		_generate_nails_in_range(_last_generated_x, _last_generated_x + chunk_size)
		_last_generated_x += chunk_size

	# Cleanup nails left from the camera
	_cleanup(camera_left_border - 100.0)

func _generate_nails_in_range(start_x: float, end_x: float) -> void:
	var steps: int = ScaleUtils.steps_from_position(start_x, step_size)
	var current_min_distance: float = ScaleUtils.scaled_value(minimal_nail_distance, nail_distance_increase_percent, steps)
	if current_min_distance > max_min_nail_distance:
		current_min_distance = max_min_nail_distance
	var width = end_x - start_x
	var height = gen_max_y - gen_min_y
	var cells_x = ceil(width / current_min_distance)
	var cells_y = ceil(height / current_min_distance)

	for i in range(cells_x):
		for j in range(cells_y):
			var cell_x = start_x + i * current_min_distance
			var cell_y = gen_min_y + j * current_min_distance
			var x = _rng.randf_range(cell_x, min(cell_x + current_min_distance, end_x))
			var y = _rng.randf_range(cell_y, min(cell_y + current_min_distance, gen_max_y))
			var pos = Vector2(x, y)

			# Check distance to existing nails (from other segments)
			var ok: bool = true
			for nail in _nails:
				# Check for validity first (rusty nails might have fallen)
				if not is_instance_valid(nail):
					continue

				# Reject if too close (use <= to be conservative)
				if pos.distance_to(nail.global_position) <= current_min_distance:
					ok = false
					break

			if ok:
				var current_rusty_probability: float = rusty_nail_probability + steps * rusty_nail_probability_increase_percent

				var type: NailType = NailType.NORMAL

				if _rng.randf() < current_rusty_probability:
					type = NailType.RUSTY
				elif _rng.randf() < boost_nail_probability:
					type = NailType.BOOST

				_spawn_nail(pos, type)

func _spawn_nail(pos: Vector2, type: NailType) -> void:
	var nail: Node2D

	match type:
		NailType.RUSTY:
			nail = _rusty_nail_pool.acquire()
			# A fallen nail hands itself back instead of freeing itself, which
			# would strand the pool's reference to it.
			if not nail.despawn_requested.is_connected(_on_rusty_nail_despawned):
				nail.despawn_requested.connect(_on_rusty_nail_despawned)
		NailType.BOOST:
			nail = _boost_nail_pool.acquire()
		_:
			nail = _normal_nail_pool.acquire()

	# Every pooled nail carries state from its previous life - a lit highlight
	# halo, an "in use" flag - not just the rusty ones that fall.
	if nail.has_method("reset"):
		nail.reset()

	nail.global_position = pos
	_nails.append(nail)

func _on_rusty_nail_despawned(nail: Node2D) -> void:
	# Drop it from _nails first, so _cleanup below does not release it a second
	# time. erase() preserves the left-to-right ordering that _cleanup's early
	# break relies on.
	_nails.erase(nail)
	_rusty_nail_pool.release(nail)

func _cleanup(cleanup_x: float) -> void:
	# Optimization: Only check nails we track, instead of get_children()
	# Because _nails is sorted by x position (creation order), we can stop
	# once we reach a nail that is still on screen.

	var nails_to_remove: int = 0

	for i in range(_nails.size()):
		var nail = _nails[i]
		if not is_instance_valid(nail):
			nails_to_remove += 1
			continue

		if nail.global_position.x < cleanup_x:
			# Identify type to release to correct pool
			# This is a bit hacky, normally we'd store type info or have the nail know its pool
			# But checking script/filename works
			if nail.scene_file_path == rusty_nail_scene.resource_path:
				_rusty_nail_pool.release(nail)
			elif nail.scene_file_path == boost_nail_scene.resource_path:
				_boost_nail_pool.release(nail)
			else:
				_normal_nail_pool.release(nail)

			nails_to_remove += 1
		else:
			# Since nails are added in order of X, if we reach one that is
			# within the screen/buffer, all subsequent ones are also safe.
			break

	# Create a new array slice if we removed anything
	if nails_to_remove > 0:
		if nails_to_remove >= _nails.size():
			_nails.clear()
		else:
			_nails = _nails.slice(nails_to_remove)
