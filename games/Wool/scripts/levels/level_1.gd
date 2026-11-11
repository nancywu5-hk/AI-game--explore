extends Node2D

## Level 1 Script
##
## Handles start icons removal (instant start)

@onready var hud: CanvasLayer = $HUD

var player: BasePlayer = null

# Only accept start input after the scene has finished loading
var _tutorial_hint_instance: Control = null
var _tutorial_timer: float = 0.0
var _waiting_for_input_after_icons: bool = false
const TUTORIAL_HINT_SCENE = preload("res://scenes/ui/tutorial_hint.tscn")

# Highscore Bar Logic
var _highscore_bar: Sprite2D = null
var _start_x_initialized: bool = false
var _start_x: float = 0.0
var _initial_highscore_to_beat: int = 0
var _highscore_visual_active: bool = false

func _ready() -> void:
	# Mark that the game has been started
	GameManager.mark_game_started()

	# First launch: the game boots straight into gameplay with no menu in front
	# of it, so this is the only place there is to ask for a name. UIManager
	# pauses the tree while the prompt is up, and the run clock does not start
	# until the first jump (GameManager.notify_run_started), so the wait costs
	# the player nothing. Deferred because the scene tree is still being swapped
	# in around us.
	if not LeaderboardManager.has_player_name():
		UIManager.open.call_deferred(&"username")

	if hud:
		hud.visible = true

	# Start waiting for player input (Tutorial logic)
	_waiting_for_input_after_icons = true
	_tutorial_timer = 0.0

	# Store initial highscore to check against
	_initial_highscore_to_beat = GameManager.highscore

	# Connect signal
	if not GameManager.highscore_beaten.is_connected(_on_highscore_beaten):
		GameManager.highscore_beaten.connect(_on_highscore_beaten)

	# Add Enemy Spawner
	var spawner_script = load("res://scripts/levels/enemy_spawner.gd")
	if spawner_script:
		var spawner = spawner_script.new()
		spawner.name = "EnemySpawner"
		add_child(spawner)

func _process(delta: float) -> void:
	# Try to find player if not found yet
	if not player:
		player = get_tree().get_first_node_in_group("player")

	# Initialize Start X for Highscore Bar positioning
	if player and not _start_x_initialized:
		_start_x = player.global_position.x
		_start_x_initialized = true
		_setup_highscore_bar()

	# Check for Highscore Crossing
	if _highscore_visual_active:
		_check_highscore_crossing()

	# Tutorial Hint Timer Logic
	if _waiting_for_input_after_icons and not _tutorial_hint_instance:
		_tutorial_timer += delta
		if _tutorial_timer >= 1.5:
			_show_tutorial_hint()

	# Note: We only accept unhandled events after the scene has loaded to avoid UI/pause interactions starting the game.


func _show_tutorial_hint() -> void:
	if not TUTORIAL_HINT_SCENE: return

	_tutorial_hint_instance = TUTORIAL_HINT_SCENE.instantiate()

	# Pass context to tutorial hint
	if player:
		var start_pos = player.global_position
		if _tutorial_hint_instance.has_method("setup"):
			_tutorial_hint_instance.setup(start_pos, player)

	if hud:
		hud.add_child(_tutorial_hint_instance)
	else:
		add_child(_tutorial_hint_instance)

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		# Ignore input if the game is paused or not in PLAYING state
		return

	if event.is_action_pressed("jump") and not event.is_echo():
		# Check tutorial dismissal
		if _waiting_for_input_after_icons:
			_waiting_for_input_after_icons = false
			if _tutorial_hint_instance:
				_tutorial_hint_instance.queue_free()
				_tutorial_hint_instance = null

# --- HIGHSCORE BAR IMPLEMENTATION ---

func _setup_highscore_bar() -> void:
	# Only show bar if we have a valid highscore to beat
	if _initial_highscore_to_beat <= 0:
		return

	# Create the visual bar
	_highscore_bar = Sprite2D.new()
	_highscore_bar.texture = load("res://assets/ui/highscore-bar.png")
	_highscore_bar.z_index = -4 # Behind nails (0/2), Front of fetzen/muster (-10/-20)

	# Rotate 90 degrees to make it vertical
	_highscore_bar.rotation = PI / 2.0

	# Calculate dimensions for scaling
	# We want to fill [PLAYABLE_HEIGHT_TOP, PLAYABLE_HEIGHT_BOTTOM]
	var top = GameManager.PLAYABLE_HEIGHT_TOP
	var bottom = GameManager.PLAYABLE_HEIGHT_BOTTOM
	var total_height = abs(top - bottom)
	var center_y = (top + bottom) / 2.0

	if _highscore_bar.texture:
		# Since we rotated 90 deg, the texture's Width becomes the visual Height
		# So we scale the X axis of the sprite
		var tex_width = _highscore_bar.texture.get_width()
		if tex_width > 0:
			_highscore_bar.scale.x = total_height / tex_width

	# Position
	# X = Start + Highscore * 10
	var bar_x = _start_x + (_initial_highscore_to_beat * 10.0)
	_highscore_bar.position = Vector2(bar_x, center_y)

	add_child(_highscore_bar)
	_highscore_visual_active = true

func _check_highscore_crossing() -> void:
	# We use GameManager distance logic to ensure consistency with "beating" the score
	var current_dist = GameManager.get_current_distance()

	if current_dist > _initial_highscore_to_beat:
		_highscore_visual_active = false
		# REMOVED: if _highscore_bar: _highscore_bar.visible = false

		# Trigger the update in GameManager (plays sound)
		GameManager.update_highscore(current_dist, GameManager.get_run_time_ms(), false)

func _on_highscore_beaten() -> void:
	# Determine if we should hide the bar (e.g. if beaten by another mechanism)
	if _highscore_visual_active:
		_highscore_visual_active = false
		# REMOVED: if _highscore_bar: _highscore_bar.visible = false
