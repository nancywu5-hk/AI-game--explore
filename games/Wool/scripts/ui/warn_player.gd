class_name WarnPlayer
extends Node2D

@onready var exclamation_mark: Sprite2D = $ExclamationMark

var target: Node2D = null
var margin: float = GameManager.SIDE_MARGIN
var vertical_margin: float = 50.0

func _ready() -> void:
	if exclamation_mark:
		_start_pulsing()

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return

	_update_position()

func _update_position() -> void:
	var viewport = get_viewport()
	if not viewport:
		return

	var camera = viewport.get_camera_2d()
	if not camera:
		return

	var screen_rect = viewport.get_visible_rect()
	# Get target's position in screen coordinates relative to the viewport (CanvasLayer)
	# Since this node will be in a CanvasLayer (HUD), (0,0) is top-left of screen.
	# But target is in world space.

	var canvas_transform = target.get_canvas_transform()
	var screen_pos = canvas_transform * target.global_position

	# Check if target is inside the screen OR on the left side
	# User wants "Only show the exclamationmarks on the right edge"
	# So if it's visible (inside) OR passed (left), we remove it.

	if screen_pos.x <= screen_rect.end.x:
		queue_free()
		return

	# Clamp position to screen edges
	# X is always Right Edge
	var clamped_x = screen_rect.end.x - margin
	var clamped_y = clamp(screen_pos.y, screen_rect.position.y + vertical_margin, screen_rect.end.y - vertical_margin)

	position = Vector2(clamped_x, clamped_y)

func _start_pulsing() -> void:
	AudioManager.play_sound(AudioManager.GAME.WARN)
	var tween = create_tween().set_loops()
	# Scale up to 2.0 (Double size)
	tween.tween_property(exclamation_mark, "scale", Vector2(2.0, 2.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Scale down to 1.6 (Double of 0.8)
	tween.tween_property(exclamation_mark, "scale", Vector2(1.6, 1.6), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

