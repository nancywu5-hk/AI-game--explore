class_name EnemySpawner
extends Node

# Config
var eagle_scene: PackedScene = preload("res://scenes/characters/enemies/eagle.tscn")
var fish_scene: PackedScene = preload("res://scenes/characters/enemies/fish.tscn")
var plant_scene: PackedScene = preload("res://scenes/characters/enemies/plant.tscn")

var spawn_distance_x: float = 500.0

# Eagle Config
var eagle_spawn_interval_min: float = 2.0
var eagle_spawn_interval_max: float = 5.0
var eagle_spawn_height_min: float = -200.0
var eagle_spawn_height_max: float = 0.0
var eagle_min_distance: int = 1000

# Fish Config
var fish_spawn_interval_min: float = 5.0
var fish_spawn_interval_max: float = 12.0
var fish_spawn_y: float = 0.0 # Approximate water level
var fish_min_distance: int = 500

# Plant Config
var plant_spawn_interval_min: float = 5.0
var plant_spawn_interval_max: float = 10.0
var plant_min_distance: int = 0
var plant_spawn_y: float = 0.0

# Plant Spacing Config
# 1000 pixels = 100m (since 10px = 1m in GameManager)
var plant_min_spacing_start: float = 1000.0
# 500 pixels = 50m
var plant_min_spacing_end: float = 500.0
# Distance at which scaling maxes out (e.g. 5000m)
var plant_spacing_scaling_distance: float = 5000.0

var _eagle_timer: float = 0.0
var _fish_timer: float = 0.0
var _plant_timer: float = 0.0
var _player: Node2D = null
var _spawn_counts: Dictionary = {}

var _active_eagle_count: int = 0
var _active_fish_count: int = 0
var _last_plant_global_x: float = -99999.0

var _eagle_pool: ObjectPool
var _fish_pool: ObjectPool
var _plant_pool: ObjectPool

func _ready() -> void:
	_eagle_pool = ObjectPool.new(eagle_scene, get_parent(), 5)
	_fish_pool = ObjectPool.new(fish_scene, get_parent(), 5)
	_plant_pool = ObjectPool.new(plant_scene, get_parent(), 5)

	# Initialize Config from GameManager (safe to access here)
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	eagle_spawn_height_max = GameManager.PLAYABLE_HEIGHT_TOP + viewport_height / 6.0
	eagle_spawn_height_min = -viewport_height / 6.0
	fish_spawn_y = GameManager.WATER_LEVEL

	_reset_eagle_timer()
	_reset_fish_timer()
	_reset_plant_timer()

func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return

	var current_dist = GameManager.get_current_distance()

	# Segment Logic
	# 0 - 500: None
	# 500 - 1000: Fish
	# 1000 - 1500: Eagle
	# 1500 - 2000: Plant
	# 2000+: All

	var spawn_fish = (current_dist >= 500 and current_dist < 1000) or current_dist >= 2000
	var spawn_eagle = (current_dist >= 1000 and current_dist < 1500) or current_dist >= 2000
	var spawn_plant = (current_dist >= 1500 and current_dist < 2000) or current_dist >= 2000

	# Process Eagle Spawning
	# Check active count constraint
	if spawn_eagle and _active_eagle_count == 0:
		_eagle_timer -= delta
		if _eagle_timer <= 0:
			_spawn_eagle()
			_reset_eagle_timer(current_dist)
	elif not spawn_eagle:
		# Keep timer ready but not firing if outside zone
		_eagle_timer = 2.0

	# Process Fish Spawning
	# Check active count constraint
	if spawn_fish and _active_fish_count == 0:
		_fish_timer -= delta
		if _fish_timer <= 0:
			_spawn_fish()
			_reset_fish_timer(current_dist)
	elif not spawn_fish:
		_fish_timer = 2.0

	# Process Plant Spawning
	if spawn_plant:
		_plant_timer -= delta
		if _plant_timer <= 0:
			# Check distance constraint before spawning
			if _can_spawn_plant(current_dist):
				_spawn_plant()
				_reset_plant_timer(current_dist)
			else:
				# Wait a bit before checking again?
				# Actually, the timer is already <= 0, so it will retry next frame
				# But to prevent spamming check every frame if we are just waiting for distance,
				# we could add a small delay or just let it spin (it's cheap).
				# However, since we reset timer AFTER spawn, if we don't spawn, timer stays <= 0.
				# This means it will check every frame until distance is met. This is fine.
				pass
	else:
		_plant_timer = 2.0

func _get_difficulty_multiplier(current_dist: float) -> float:
	if current_dist <= 2000:
		return 1.0

	# Every 500m after 2000m, increase difficulty (reduce time)
	var steps = int((current_dist - 2000) / 500.0)
	if steps <= 0: return 1.0

	# Reduce interval by 10% per step, capped at 50% (0.5 multiplier)
	var multiplier = pow(0.9, steps)
	return max(0.5, multiplier)

func _get_current_min_plant_spacing(current_dist: int) -> float:
	# Calculate interpolation factor (0.0 to 1.0)
	# We want spacing start at 0 dist and spacing end at scaling_distance
	var t: float = clamp(float(current_dist) / plant_spacing_scaling_distance, 0.0, 1.0)

	# Lerp from start (1000) to end (500)
	return lerp(plant_min_spacing_start, plant_min_spacing_end, t)

func _can_spawn_plant(current_dist: int) -> bool:
	if not _player: return false

	var cam = _player.get_viewport().get_camera_2d()
	if not cam: return false

	# Calculate where it WOULD spawn
	var cam_pos = cam.global_position
	var viewport_rect = _player.get_viewport_rect()
	var camera_zoom = cam.zoom
	var visible_width = viewport_rect.size.x / camera_zoom.x
	var spawn_x = cam_pos.x + (visible_width * 0.5) + spawn_distance_x

	var min_spacing = _get_current_min_plant_spacing(current_dist)

	return (spawn_x - _last_plant_global_x) >= min_spacing

func _reset_eagle_timer(current_dist: float = 0.0) -> void:
	var mult = _get_difficulty_multiplier(current_dist)
	_eagle_timer = randf_range(eagle_spawn_interval_min, eagle_spawn_interval_max) * mult

func _reset_fish_timer(current_dist: float = 0.0) -> void:
	var mult = _get_difficulty_multiplier(current_dist)
	_fish_timer = randf_range(fish_spawn_interval_min, fish_spawn_interval_max) * mult

func _reset_plant_timer(current_dist: float = 0.0) -> void:
	var mult = _get_difficulty_multiplier(current_dist)
	_plant_timer = randf_range(plant_spawn_interval_min, plant_spawn_interval_max) * mult

func _spawn_eagle() -> void:
	if not _player: return

	# Get camera center position
	var cam_pos = _player.get_viewport().get_camera_2d().global_position
	# Viewport rect size
	var viewport_rect = _player.get_viewport_rect()
	# Size scaled by zoom (assuming camera might have zoom, though usually 1.0)
	var camera_zoom = _player.get_viewport().get_camera_2d().zoom
	var visible_width = viewport_rect.size.x / camera_zoom.x

	# Spawn 'offset' pixels to the right of the RIGHT EDGE of the camera
	# Camera is centered, so right edge is cam_pos.x + visible_width/2
	var spawn_x = cam_pos.x + (visible_width * 0.5) + spawn_distance_x

	var spawn_y = randf_range(eagle_spawn_height_max, eagle_spawn_height_min)

	var eagle = _eagle_pool.acquire()
	if eagle.has_signal("despawn_requested"):
		if not eagle.despawn_requested.is_connected(_on_enemy_despawn_requested):
			eagle.despawn_requested.connect(_on_enemy_despawn_requested)

	eagle.global_position = Vector2(spawn_x, spawn_y)

	# Reset state?
	if eagle.has_method("reset"): eagle.reset()
	# Or manually reset velocity/etc if exposed.
	# Ideally add reset() to BaseEnemy

	_add_enemy(eagle, "Eagle")
	_active_eagle_count += 1

func _spawn_fish() -> void:
	if not _player: return

	var cam_pos = _player.get_viewport().get_camera_2d().global_position
	var viewport_rect = _player.get_viewport_rect()
	var camera_zoom = _player.get_viewport().get_camera_2d().zoom
	var visible_width = viewport_rect.size.x / camera_zoom.x

	var spawn_x = cam_pos.x + (visible_width * 0.5) +  spawn_distance_x * 0.5
	var spawn_y = fish_spawn_y

	var fish = _fish_pool.acquire()
	if fish.has_signal("despawn_requested"):
		if not fish.despawn_requested.is_connected(_on_enemy_despawn_requested):
			fish.despawn_requested.connect(_on_enemy_despawn_requested)

	fish.global_position = Vector2(spawn_x, spawn_y)
	if fish.has_method("reset"): fish.reset()

	_add_enemy(fish, "Fish")
	_active_fish_count += 1

func _spawn_plant() -> void:
	if not _player: return

	var cam_pos = _player.get_viewport().get_camera_2d().global_position
	var viewport_rect = _player.get_viewport_rect()
	var camera_zoom = _player.get_viewport().get_camera_2d().zoom
	var visible_width = viewport_rect.size.x / camera_zoom.x

	var spawn_x = cam_pos.x + (visible_width * 0.5) + spawn_distance_x
	var spawn_y = plant_spawn_y

	var plant = _plant_pool.acquire()
	if plant.has_signal("despawn_requested"):
		if not plant.despawn_requested.is_connected(_on_enemy_despawn_requested):
			plant.despawn_requested.connect(_on_enemy_despawn_requested)

	plant.global_position = Vector2(spawn_x, spawn_y)
	if plant.has_method("reset"): plant.reset()

	_add_enemy(plant, "Plant")
	_last_plant_global_x = spawn_x

func _add_enemy(enemy: Node, type_name: String) -> void:
	# No longer adding child here as pool handles it, but we might need to call ready?
	# ObjectPool adds child when creating. When acquiring, it just sets visible.

	# Initialize count for this type if not exists
	if not _spawn_counts.has(type_name):
		_spawn_counts[type_name] = 0

	# Apply warning to the first few enemies of this specific type
	_spawn_counts[type_name] += 1

	if enemy.has_method("show_spawn_warning"):
		enemy.call_deferred("show_spawn_warning")

func _on_enemy_despawn_requested(enemy: Node) -> void:
	# Determine which pool it belongs to based on type
	if enemy is Eagle:
		_eagle_pool.release(enemy)
		_active_eagle_count = max(0, _active_eagle_count - 1)
	elif enemy is Fish:
		_fish_pool.release(enemy)
		_active_fish_count = max(0, _active_fish_count - 1)
	elif enemy is Plant:
		_plant_pool.release(enemy)
