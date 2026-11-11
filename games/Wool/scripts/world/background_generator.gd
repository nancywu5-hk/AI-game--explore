extends Node2D

## Background Generator
##
## Generates infinite background tiles that repeat horizontally
## Background spans from y=0 to y=-1755

@export var background_folder: String = "res://assets/map/fetzen"
@export var pattern_folder: String = "res://assets/map/muster"
@export var pattern_chance: float = 0.50
@export var max_patterns_per_tile: int = 5
@export var parallax_factor_x: float = 1.0
@export var decoration_parallax_factor_x: float = 1.0
@export var background_modulate: Color = Color(1.0, 1.0, 1.0)
@export var decoration_cell_size: float = 500.0

var base_background_texture = preload("res://assets/map/background.png")

# Preload textures to ensure they are included in exports
const BACKGROUND_TEXTURES: Array[Texture2D] = [
	preload("res://assets/map/background.png"),
]
const FETZEN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/map/fetzen/1.png"),
	preload("res://assets/map/fetzen/2.png"),
	preload("res://assets/map/fetzen/3.png"),
	preload("res://assets/map/fetzen/4.png"),
	preload("res://assets/map/fetzen/5.png"),
]
const PATTERN_TEXTURES: Array[Texture2D] = [

]
const PIN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/map/pin-blue.png"),
	preload("res://assets/map/pin-red.png"),
	preload("res://assets/map/pin-yellow.png"),
]

@onready var parallax_layer: ParallaxLayer = get_node_or_null("../ParallaxBackground/ParallaxLayer")
var decoration_layer: ParallaxLayer = null

var _player: BasePlayer = null
var _camera_width: float = 0.0

var _last_bg_x: float = 0.0
var _last_deco_x: float = 0.0
var _last_camera_check_x: float = -1000.0

var _background_tiles: Array[Sprite2D] = [] # Base background tiles
# We track decoration nodes separately if needed, or just keep them in a list for cleanup
var _decoration_nodes: Array[Sprite2D] = []

var _background_width: float = 0.0  # Width of a single background tile
var _background_height: float = 0.0

# Runtime-loaded pattern textures and pattern nodes
var _pattern_textures: Array[Texture2D] = []
var _fetzen_textures: Array[Texture2D] = []
var _pin_textures: Array[Texture2D] = []

# Runtime-loaded textures from `background_folder`
var _background_textures: Array[Texture2D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _decoration_pool: ObjectPool
var _sprite_scene: PackedScene = preload("res://scenes/utils/pooled_sprite.tscn")

const DECORATION_SHADOW_NAME: String = "FetzenShadow"

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_camera_width = get_viewport().get_visible_rect().size.x
	else:
		_camera_width = get_viewport().get_visible_rect().size.x

	_background_height = abs(GameManager.PLAYABLE_HEIGHT_TOP - GameManager.PLAYABLE_HEIGHT_BOTTOM)

	# Use preloaded textures
	_background_textures = BACKGROUND_TEXTURES.duplicate()
	_fetzen_textures = FETZEN_TEXTURES.duplicate()
	_pin_textures = PIN_TEXTURES.duplicate()
	# remove background.png from random textures if added there by mistake

	_pattern_textures = PATTERN_TEXTURES.duplicate()

	# Randomize RNG for tile selection and pattern placement
	_rng.randomize()

	if not base_background_texture:
		return

	# Calculate scale for background base
	var bg_h = base_background_texture.get_height()
	var bg_w = base_background_texture.get_width()
	var bg_scale = 1.0
	if bg_h > 0:
		bg_scale = _background_height / bg_h

	_background_width = bg_w * bg_scale

	# Setup Parallax Layers
	if parallax_layer:
		# Base Layer configuration
		parallax_layer.motion_scale = Vector2(parallax_factor_x, 1.0)

		# Create Decoration Layer
		decoration_layer = ParallaxLayer.new()
		decoration_layer.name = "DecorationLayer"
		decoration_layer.motion_scale = Vector2(decoration_parallax_factor_x, 1.0)
		parallax_layer.get_parent().add_child(decoration_layer)
		# Ensure it's rendered in correct order.
		# Base bg is z -20, decorations -10/-5.

		# Initial generation
		var bg_gen_end: float = 2.0 * _camera_width

		# Decor generation (needs its own coordination system)
		# Initialize pool on the decoration layer
		_decoration_pool = ObjectPool.new(_sprite_scene, decoration_layer, 50)

		_generate_bg_until(bg_gen_end)
		_generate_deco_until(bg_gen_end)

func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return

	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if not _player or not _player.camera:
		return

	if not parallax_layer or not decoration_layer:
		# Re-acquire logic if lost? Usually not needed if setup in _ready
		return

	if _background_width <= 0:
		return

	var camera = _player.camera
	var visible_half_width = (_camera_width / 2.0) / camera.zoom.x

	# Optimization: Throttle updates
	if abs(camera.global_position.x - _last_camera_check_x) < 100.0:
		return
	_last_camera_check_x = camera.global_position.x

	# --- Base Background Generation ---
	var bg_layer_center_x = camera.global_position.x * parallax_factor_x
	var bg_layer_right = bg_layer_center_x + visible_half_width
	var bg_gen_end = bg_layer_right + _camera_width

	# Only generate one chunk per frame if behind
	if _last_bg_x < bg_gen_end:
		var chunk_w = _spawn_base_chunk(_last_bg_x)
		if chunk_w <= 0.0: chunk_w = 1.0
		_last_bg_x += chunk_w

	_cleanup_bg(bg_layer_center_x - visible_half_width - _background_width)

	# --- Decoration Generation ---
	var deco_layer_center_x = camera.global_position.x * decoration_parallax_factor_x
	var deco_layer_right = deco_layer_center_x + visible_half_width
	var deco_gen_end = deco_layer_right + _camera_width

	# Only generate one chunk cell per frame if behind
	if _last_deco_x < deco_gen_end:
		_spawn_deco_chunk(_last_deco_x, decoration_cell_size)
		_last_deco_x += decoration_cell_size

	_cleanup_deco(deco_layer_center_x - visible_half_width - 500.0) # 500 buffer

func _generate_bg_until(end_x: float) -> void:
	var x: float = max(_last_bg_x, 0.0)
	while x < end_x:
		var chunk_w = _spawn_base_chunk(x)
		if chunk_w <= 0.0:
			chunk_w = 1.0
		x += chunk_w
	_last_bg_x = x

func _generate_deco_until(end_x: float) -> void:
	var x: float = max(_last_deco_x, 0.0)
	# Decorations are spawned in 250 width chunks (grid columns)
	# We can just increment by cell_size

	while x < end_x:
		_spawn_deco_chunk(x, decoration_cell_size)
		x += decoration_cell_size
	_last_deco_x = x

func _spawn_base_chunk(x: float) -> float:
	if not parallax_layer or not base_background_texture:
		return 0.0

	var sprite := Sprite2D.new()
	sprite.texture = base_background_texture
	sprite.z_index = -20
	sprite.modulate = background_modulate

	var bg_h = base_background_texture.get_height()
	var bg_scale = 1.0
	if bg_h > 0:
		bg_scale = _background_height / bg_h

	sprite.scale = Vector2(bg_scale, bg_scale)

	# Center Y
	var center_y = (GameManager.PLAYABLE_HEIGHT_BOTTOM + GameManager.PLAYABLE_HEIGHT_TOP) / 2.0
	var chunk_width = base_background_texture.get_width() * bg_scale
	sprite.position = Vector2(x + chunk_width / 2.0, center_y)

	parallax_layer.add_child(sprite)
	_background_tiles.append(sprite)

	return chunk_width

func _spawn_deco_chunk(x: float, width: float) -> void:
	if not decoration_layer:
		return

	# We assume 'width' is effectively one column width, but let's stick to the grid logic
	# Playable Height logic
	# Playable Height logic
	var num_rows = ceil(_background_height / decoration_cell_size)
	var start_y = GameManager.PLAYABLE_HEIGHT_TOP

	for row in range(num_rows):
		if _rng.randf() > pattern_chance:
			continue

		var cell_y = start_y + (row * decoration_cell_size)


		var dec_sprite = _decoration_pool.acquire() as Sprite2D
		# Reset properties
		dec_sprite.offset = Vector2.ZERO

		# The shadow is built once per pooled sprite and then reused. Freeing it
		# and allocating a replacement on every acquire churned one node per
		# decoration, which is the exact cost the pool exists to avoid.
		var fetzen_shadow := _get_decoration_shadow(dec_sprite)
		fetzen_shadow.visible = false

		var use_fetzen = _rng.randf() > 0.5
		var tex: Texture2D = null

		if use_fetzen and _fetzen_textures.size() > 0:
			tex = _fetzen_textures[_rng.randi() % _fetzen_textures.size()]
			dec_sprite.z_index = -10
		elif _pattern_textures.size() > 0:
			tex = _pattern_textures[_rng.randi() % _pattern_textures.size()]
			dec_sprite.z_index = -5

		if tex:
			dec_sprite.texture = tex

			var padding = 20.0
			var offset_x = _rng.randf_range(padding, decoration_cell_size - padding)
			var offset_y = _rng.randf_range(padding, decoration_cell_size - padding)

			var final_x = x + offset_x
			var final_y = cell_y + offset_y

			dec_sprite.position = Vector2(final_x, final_y)

			var s = 1.0
			if use_fetzen:
				s = _rng.randf_range(0.1, 0.3)

				# FETZEN SHADOW (Way smaller than others)
				# 5px visual offset
				fetzen_shadow.texture = tex

				# Position relative to fetzen (scaled)
				# Only apply offset, no position since it's child (0,0)
				fetzen_shadow.position = Vector2(5, 5) / s
				fetzen_shadow.scale = Vector2(1.0, 1.0) # Inherit scale
				fetzen_shadow.visible = true
			else:
				s = _rng.randf_range(0.4, 0.8)

			dec_sprite.scale = Vector2(s, s)

			# Rotation
			if use_fetzen:
				# Increased "Fetzen" rotation
				dec_sprite.rotation = _rng.randf_range(-0.35, 0.35)
			else:
				dec_sprite.rotation = _rng.randf_range(-0.1, 0.1)

			if dec_sprite.get_parent() != decoration_layer:
				decoration_layer.add_child(dec_sprite)
			_decoration_nodes.append(dec_sprite)

## The shadow node a pooled decoration sprite reuses across acquires, created on
## that sprite's first use. Only the texture, position and visibility change per
## decoration, so the node itself never needs replacing.
func _get_decoration_shadow(dec_sprite: Sprite2D) -> Sprite2D:
	var shadow := dec_sprite.get_node_or_null(DECORATION_SHADOW_NAME) as Sprite2D
	if shadow:
		return shadow

	shadow = Sprite2D.new()
	shadow.name = DECORATION_SHADOW_NAME
	shadow.modulate = Color(0, 0, 0, 0.5)
	shadow.z_index = -1 # Behind fetzen
	dec_sprite.add_child(shadow)
	return shadow

func _load_background_textures_from_folder() -> void:
	_background_textures.clear()
	var dir := DirAccess.open(background_folder)
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if not dir.current_is_dir():
				var ext := file.get_extension().to_lower()
				if ext in ["png", "jpg", "jpeg", "webp"]:
					var path := "%s/%s" % [background_folder, file]
					var tex := ResourceLoader.load(path) as Texture2D
					if tex:
						_background_textures.append(tex)
			file = dir.get_next()
		dir.list_dir_end()

func _cleanup_bg(cleanup_x: float) -> void:
	# Efficient cleanup: arrays are sorted by position.x
	var remove_count: int = 0

	for i in range(_background_tiles.size()):
		var tile = _background_tiles[i]
		if not is_instance_valid(tile):
			remove_count += 1
			continue

		# Check if the right edge of the tile is past the cleanup line
		# Tile position is center or top-left? Based on spawn it's center.
		# width is roughly _background_width
		# To be safe, we check if position.x is well behind cleanup_x
		if tile.position.x < cleanup_x:
			tile.queue_free()
			remove_count += 1
		else:
			break

	if remove_count > 0:
		if remove_count >= _background_tiles.size():
			_background_tiles.clear()
		else:
			_background_tiles = _background_tiles.slice(remove_count)

func _cleanup_deco(cleanup_x: float) -> void:
	var remove_count: int = 0

	for i in range(_decoration_nodes.size()):
		var node = _decoration_nodes[i]
		if not is_instance_valid(node):
			remove_count += 1
			continue

		if node.position.x < cleanup_x:
			_decoration_pool.release(node)
			remove_count += 1
		else:
			break

	if remove_count > 0:
		if remove_count >= _decoration_nodes.size():
			_decoration_nodes.clear()
		else:
			_decoration_nodes = _decoration_nodes.slice(remove_count)
