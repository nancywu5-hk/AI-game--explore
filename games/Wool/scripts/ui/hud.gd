extends CanvasLayer

@onready var pause_button: Button = $PauseButton
@onready var current_distance_label: Label = $CurrentDistance
@onready var rusty_nail_timer: Control = $RustyNailTimer
@onready var rusty_nail_timer_bg: Panel = $RustyNailTimer/Background
@onready var rusty_nail_timer_fill: Panel = $RustyNailTimer/Fill
@onready var off_screen_indicator: TextureRect = $OffScreenIndicator

const UI_TOP_MARGIN: float = 20.0

var player: BasePlayer = null
var _last_pause_press_ms: int = -10000
var _last_shown_distance: int = -1


func _ready() -> void:
	GameManager.rusty_nail_timer_started.connect(_on_rusty_nail_timer_started)
	GameManager.rusty_nail_timer_updated.connect(_on_rusty_nail_timer_updated)
	GameManager.rusty_nail_timer_stopped.connect(_on_rusty_nail_timer_stopped)
	GameManager.state_changed.connect(_on_game_state_changed)
	get_tree().root.size_changed.connect(_update_layout)

	rusty_nail_timer.visible = false
	# Ensure initial fill matches (full)
	rusty_nail_timer_fill.offset_left = rusty_nail_timer.offset_left
	rusty_nail_timer_fill.offset_right = rusty_nail_timer.offset_right
	# Make button background transparent (icon only)
	var flat_style := StyleBoxFlat.new()
	flat_style.bg_color = Color(0,0,0,0)
	flat_style.corner_radius_top_left = 20
	flat_style.corner_radius_top_right = 20
	flat_style.corner_radius_bottom_left = 20
	flat_style.corner_radius_bottom_right = 20

	pause_button.add_theme_stylebox_override("normal", flat_style)
	pause_button.add_theme_stylebox_override("hover", flat_style)

	# Light gray feedback for pressed/focus
	var feedback_style := flat_style.duplicate()
	feedback_style.bg_color = Color(1, 1, 1, 0.2)
	pause_button.add_theme_stylebox_override("pressed", feedback_style)
	pause_button.add_theme_stylebox_override("focus", feedback_style)

	# Configure RustyNailTimer rounded visuals
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.5)
	bg_style.set_corner_radius_all(25) # Half of 50px height
	rusty_nail_timer_bg.add_theme_stylebox_override("panel", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(1, 1, 1, 0.95)
	fill_style.set_corner_radius_all(25)
	rusty_nail_timer_fill.add_theme_stylebox_override("panel", fill_style)

	# Make labels background transparent
	if current_distance_label:
		var transparent_style = StyleBoxEmpty.new()
		current_distance_label.add_theme_stylebox_override("normal", transparent_style)


	# Ensure the pause button triggers on touch (connect pressed signal)
	if pause_button:
		pause_button.pressed.connect(_on_pause_pressed)

	call_deferred("_update_layout")

func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var base_size: float = min(viewport_size.x, viewport_size.y)
	var horizontal_margin := clampf(viewport_size.x * 0.05, 20.0, 150.0)
	var top_margin := clampf(viewport_size.y * 0.05, 20.0, 100.0)
	var pause_size := clampf(base_size * 0.14, 72.0, 150.0)
	var distance_width := clampf(viewport_size.x * 0.3, 180.0, 500.0)
	var timer_width := clampf(viewport_size.x * 0.4, 220.0, 600.0)
	var timer_height := clampf(viewport_size.y * 0.06, 32.0, 50.0)

	pause_button.offset_left = horizontal_margin
	pause_button.offset_top = top_margin
	pause_button.offset_right = horizontal_margin + pause_size
	pause_button.offset_bottom = top_margin + pause_size

	current_distance_label.offset_left = -(horizontal_margin + distance_width)
	current_distance_label.offset_top = top_margin
	current_distance_label.offset_right = -horizontal_margin
	current_distance_label.offset_bottom = top_margin + clampf(base_size * 0.13, 60.0, 144.0)
	current_distance_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.09, 36.0, 100.0)))

	rusty_nail_timer.offset_left = -timer_width / 2.0
	rusty_nail_timer.offset_top = -(top_margin + timer_height + 24.0)
	rusty_nail_timer.offset_right = timer_width / 2.0
	rusty_nail_timer.offset_bottom = -(top_margin + 24.0)

func _on_pause_pressed() -> void:
	var now_ms: int = Time.get_ticks_msec()
	# Touch input can trigger both Button.pressed and ScreenTouch in the same frame.
	if now_ms - _last_pause_press_ms < 250:
		return
	_last_pause_press_ms = now_ms

	AudioManager.play_sound(AudioManager.GAME.CLICK)
	# Prevent a simultaneous jump by ignoring input for a short moment
	GameManager.ignore_input_for(0.15)
	GameManager.toggle_pause()


func _input(event: InputEvent) -> void:
	# Explicitly handle touch for the pause button to support multi-touch
	# (e.g. holding grapple (finger 1) and hitting pause (finger 2))
	if event is InputEventScreenTouch and event.pressed:
		if pause_button and pause_button.is_visible_in_tree():
			if pause_button.get_global_rect().has_point(event.position):
				_on_pause_pressed()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")

	if player:
		_update_off_screen_indicator()

	# The distance only ticks over once per metre, so formatting a fresh string
	# every frame just to assign the same value is wasted allocation.
	if current_distance_label:
		var distance_meters: int = GameManager.max_run_distance
		if distance_meters != _last_shown_distance:
			_last_shown_distance = distance_meters
			current_distance_label.text = str(distance_meters) + "m"


func _on_rusty_nail_timer_started(duration: float) -> void:
	rusty_nail_timer.visible = true
	# Max fill (no progress elapsed)
	rusty_nail_timer_fill.offset_left = rusty_nail_timer.offset_left
	rusty_nail_timer_fill.offset_right = rusty_nail_timer.offset_right

func _on_rusty_nail_timer_updated(progress: float) -> void:
	if not rusty_nail_timer.visible:
		rusty_nail_timer.visible = true

	# progress is 0..1 where 1 = timer finished
	var total_width := rusty_nail_timer.offset_right - rusty_nail_timer.offset_left
	var fill_width := total_width * (1.0 - progress)
	var half := fill_width * 0.5
	rusty_nail_timer_fill.offset_left = -half
	rusty_nail_timer_fill.offset_right = half

	# Update color: White -> Red as it progresses
	var sb = rusty_nail_timer_fill.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.bg_color = Color.WHITE.lerp(Color(1, 0, 0, 1), progress)

func _on_rusty_nail_timer_stopped() -> void:
	rusty_nail_timer.visible = false

func _on_game_state_changed(state: int) -> void:
	# Keep gameplay HUD controls hidden while overlays are open.
	var show_pause := state == GameManager.GameState.PLAYING
	if pause_button:
		pause_button.visible = show_pause

func _update_off_screen_indicator() -> void:
	if not off_screen_indicator:
		return

	# Get player screen position
	var screen_pos = player.get_global_transform_with_canvas().origin
	var viewport_rect = get_viewport().get_visible_rect()

	# Margin to keep the arrow fully on screen (approx half icon size)
	# Margin to keep the arrow fully on screen
	var margin_x = GameManager.SIDE_MARGIN

	# Only show if player is ABOVE the screen (y < 0)
	if screen_pos.y >= 0:
		# Player is visible OR below screen
		off_screen_indicator.visible = false
	else:
		# Player is off-screen (ABOVE)
		off_screen_indicator.visible = true

		# Clamp X position to screen edges with margin, FIX Y to top margin
		var clamped_x = clamp(screen_pos.x, viewport_rect.position.x + margin_x, viewport_rect.end.x - margin_x)

		# Align TOP of indicator with UI_TOP_MARGIN
		# Indicator pivot is at center (90, 90).
		# If Top Edge = UI_TOP_MARGIN, then Center Y = UI_TOP_MARGIN + PivotY
		var pivot_y = off_screen_indicator.pivot_offset.y
		var scale_y = off_screen_indicator.scale.y
		var clamped_y = UI_TOP_MARGIN + (pivot_y * scale_y)

		off_screen_indicator.position = Vector2(clamped_x, clamped_y) - off_screen_indicator.pivot_offset

		# Rotate to point at player
		# Adjusted to + PI / 2.0 based on request "rotated by 180" relative to last fix (-PI/2).
		var to_player = screen_pos - Vector2(clamped_x, clamped_y)
		off_screen_indicator.rotation = to_player.angle() - PI / 2.0 + PI
