extends Control

# References passed via setup
var _start_pos: Vector2
var _player_ref: Node2D = null
var _shadow_wool: Node2D = null
var _loop_tween: Tween
var _ripple_tween: Tween

const WOOL_SCENE = preload("res://scenes/characters/players/wool.tscn")

@onready var hand: TextureRect = $Hand
@onready var circle: TextureRect = $Circle

var _has_context: bool = false
var _is_initialized: bool = false
var _is_looping: bool = false

var _player_scale: Vector2 = Vector2(0.1, 0.1)
var _touch_pos: Vector2

func setup(start_pos: Vector2, player_ref: Node2D = null) -> void:
	_start_pos = start_pos
	if player_ref:
		_player_ref = player_ref
		_player_scale = player_ref.scale
	_has_context = true

	if is_inside_tree() and not _is_initialized:
		_initialize_content()

func _ready() -> void:
	# CRITICAL: Do not block input!
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.z_index = 1 # Ensure hand is drawn on top of the circle

	if _has_context and not _is_initialized:
		_initialize_content()

	if is_inside_tree() and not _is_initialized:
		_initialize_content()

func _initialize_content() -> void:
	_is_initialized = true
	_create_shadow_wool()
	_start_tutorial_loop()

func _create_shadow_wool() -> void:
	if not WOOL_SCENE: return

	# Update start position if player ref is available (ensure exact match)
	if _player_ref and is_instance_valid(_player_ref):
		_start_pos = _player_ref.global_position
		_player_scale = _player_ref.scale

	_shadow_wool = WOOL_SCENE.instantiate()
	_shadow_wool.modulate = Color(1, 1, 1, 0.5)
	_shadow_wool.z_index = 0

	# Attach Shadow Script logic
	_shadow_wool.set_script(load("res://scripts/characters/shadow_wool.gd"))

	# Force Scale
	_shadow_wool.scale = _player_scale

	# DO NOT disable logic! Physics must run.
	_shadow_wool.set_process(true)
	_shadow_wool.set_physics_process(true)
	_shadow_wool.set_process_unhandled_input(false) # Input handled manually
	_shadow_wool.set_process_input(false)

	# Add to WORLD
	get_tree().root.add_child(_shadow_wool)

	_shadow_wool.global_position = _start_pos
	_shadow_wool.visible = false

func _start_tutorial_loop() -> void:
	if _is_looping: return
	_is_looping = true
	_run_unified_loop()

# === UNIFIED LOOP ===
func _run_unified_loop() -> void:
	if not is_inside_tree() or not _shadow_wool:
		_is_looping = false
		return

	# 1. Reset State
	_reset_shadow_wool()

	# Fixed position: Center of bottom right quarter
	# X = 3/4 Width
	# Y = 3/4 Height (assuming 1/4 from bottom)
	var vp_size = get_viewport_rect().size
	_touch_pos = Vector2(vp_size.x * 1/2, vp_size.y * 1/2)

	_reset_visuals(_touch_pos)

	# 2. Start Timeline
	if _loop_tween: _loop_tween.kill()
	# Note: We use a single tween for the sequence to ensure perfect sync
	_loop_tween = create_tween()

	# --- PHASE 0: PREPARATION (0.0s - 0.3s) ---
	# Hand Moves In
	# Adjust target pos so the finger tip (pivot) lands on target
	# Assuming pivot_offset is set correctly on the hand texture
	# IMPORTANT: Must account for rotation and scale!
	# The visual vector from Top-Left to Pivot is: (PivotOffset * Scale).rotated(Rotation)
	var visual_offset = (hand.pivot_offset * hand.scale).rotated(hand.rotation)
	var target_hand_pos = _touch_pos - visual_offset
	var start_hand_pos = target_hand_pos + Vector2(250, 150)

	hand.global_position = start_hand_pos

	_loop_tween.parallel().tween_property(hand, "modulate:a", 1.0, 0.3)
	_loop_tween.parallel().tween_property(hand, "global_position", target_hand_pos, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


	# --- PHASE 1: JUMP 1 (TAP) (0.3s - 0.4s) ---
	# Hand Presses (0.1s)
	_loop_tween.tween_callback(func(): _animate_press(0.1))
	_loop_tween.tween_interval(0.1)

	# IMPACT at T+0.4s
	_loop_tween.tween_callback(func():
		_trigger_ripple()
		if _shadow_wool:
			_shadow_wool.visible = true
			_shadow_wool.sim_press_jump()
			_shadow_wool.sim_release_jump()
	)

	# --- PHASE 2: INTERVAL (0.4s - 0.6s) ---
	_loop_tween.tween_callback(func(): _animate_lift(0.5))
	_loop_tween.tween_interval(0.5)

	# --- PHASE 3: JUMP 2 PREP (0.6s - 0.7s) ---
	_loop_tween.tween_callback(func(): _animate_press(0.1))
	_loop_tween.tween_interval(0.1)

	# --- PHASE 4: JUMP 2 HOLD (0.7s - 1.4s) ---
	# IMPACT at T+0.7s (Exactly 0.3s after first jump)
	_loop_tween.tween_callback(func():
		_trigger_ripple()
		if _shadow_wool:
			_shadow_wool.sim_press_jump()
	)

	# Hold for 0.7s
	_loop_tween.tween_interval(0.6)

	# --- PHASE 5: RELEASE (1.4s) ---
	_loop_tween.tween_callback(func():
		if _shadow_wool:
			_shadow_wool.sim_release_jump()

		# Visual Release
		_animate_lift(0.2)
	)
	_loop_tween.parallel().tween_property(hand, "modulate:a", 0.0, 0.5)
	if _shadow_wool:
		_loop_tween.parallel().tween_property(_shadow_wool, "modulate:a", 0.0, 0.5).set_delay(1.0)

	# --- PHASE 6: RESTART ---
	_loop_tween.tween_interval(3)
	_loop_tween.tween_callback(func(): _run_unified_loop())

func _reset_shadow_wool() -> void:
	if not _shadow_wool: return

	# Update start position to match current player position perfectly
	if _player_ref and is_instance_valid(_player_ref):
		_start_pos = _player_ref.global_position
		# Also match velocity to ensure seamless overlap if moving slightly
		_shadow_wool.velocity = _player_ref.velocity
	else:
		_shadow_wool.velocity = Vector2.ZERO

	_shadow_wool.visible = false
	_shadow_wool.global_position = _start_pos
	_shadow_wool.rotation = 0
	_shadow_wool.modulate.a = 0.5

	# Reset grapple state
	if _shadow_wool.grappling_feature:
		_shadow_wool.grappling_feature.deactivate() # Clean reset
		if _shadow_wool.grappling_feature.get_target_nail():
			_shadow_wool.grappling_feature.release()

	# Force skin reset if needed
	if _shadow_wool.has_node("Skin"):
		_shadow_wool.get_node("Skin").position = Vector2.ZERO
		_shadow_wool.get_node("Skin").rotation = 0

func _reset_visuals(screen_pos: Vector2) -> void:
	if _ripple_tween: _ripple_tween.kill()
	hand.scale = Vector2(-0.5, 0.5)
	hand.modulate.a = 0.0

	_reset_circle_state()
	circle.global_position = screen_pos - (circle.size * circle.scale / 2.0)

func _animate_press(duration: float) -> void:
	var t = create_tween()
	t.tween_property(hand, "scale", Vector2(-0.45, 0.45), duration)

func _animate_lift(duration: float) -> void:
	var t = create_tween()
	t.tween_property(hand, "scale", Vector2(-0.5, 0.5), duration)

func _trigger_ripple() -> void:
	if _ripple_tween: _ripple_tween.kill()
	_reset_circle_state()
	_ripple_tween = create_tween()
	_ripple_tween.tween_property(circle, "modulate:a", 1.0, 0.0)
	_ripple_tween.parallel().tween_property(circle, "scale", Vector2(1.0, 1.0), 0.3)
	_ripple_tween.parallel().tween_property(circle, "modulate:a", 0.0, 0.3).set_delay(0.1)

func _reset_circle_state() -> void:
	circle.scale = Vector2.ONE * 0.25
	circle.modulate.a = 0.0
	# Recenter assuming scale 0.25
	circle.global_position = _touch_pos - (circle.size * circle.scale / 2.0)

func _world_to_screen(world_pos: Vector2) -> Vector2:
	var cam = get_viewport().get_camera_2d()
	if cam:
		return (world_pos - cam.global_position) * cam.zoom + get_viewport_rect().size / 2.0
	return world_pos

func _exit_tree() -> void:
	_is_looping = false
	if _loop_tween: _loop_tween.kill()
	if _ripple_tween: _ripple_tween.kill()
	if _shadow_wool and is_instance_valid(_shadow_wool):
		_shadow_wool.queue_free()
