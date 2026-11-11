extends HSlider

class_name RollingSlider

@export var texture: Texture2D
@export var scale_factor: float = 0.2
## Turns per full sweep of the slider. Positive so the knot rolls the way it
## travels: +Y is down in 2D, so a positive angle is clockwise on screen, which
## is what a ball moving right does.
@export var rotation_speed: float = 15.0

@export var track_height: float = 20.0
@export var track_color: Color = Color(0.18, 0.18, 0.18, 1.0)
@export var fill_color: Color = Color(0.44, 0.41, 0.53, 1.0)

var _sprite: Sprite2D
var _grabber_width: float = 0.0

func _ready() -> void:
	# 1. Setup the Sprite
	_sprite = Sprite2D.new()
	if texture:
		_sprite.texture = texture
	else:
		_sprite.texture = load("res://assets/character/spucki/spucki-platform.png")

	_sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(_sprite)

	# 2. Setup the transparent grabber (Hitbox)
	var img_size = _sprite.texture.get_size() * scale_factor
	_grabber_width = img_size.x

	var img = Image.create(int(img_size.x), int(img_size.y), false, Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img)

	add_theme_icon_override("grabber", tex)
	add_theme_icon_override("grabber_highlight", tex)
	add_theme_icon_override("tick", tex)

	# 3. Make built-in track/fill invisible (we draw our own)
	var empty = StyleBoxEmpty.new()
	add_theme_stylebox_override("slider", empty)
	add_theme_stylebox_override("grabber_area", empty)
	add_theme_stylebox_override("grabber_area_highlight", empty)

	# 4. Update initial pos
	_update_sprite()

	# Signals
	value_changed.connect(_on_value_changed)
	resized.connect(_on_resized)

func _on_value_changed(_val: float) -> void:
	_update_sprite()
	queue_redraw()

func _on_resized() -> void:
	_update_sprite()
	queue_redraw()

func _draw() -> void:
	var cy = size.y / 2.0
	var radius = track_height / 2.0
	var margin = _grabber_width / 2.0

	# Track background (full width, pill-shaped)
	var track_rect = Rect2(margin, cy - radius, size.x - _grabber_width, track_height)
	draw_rect(track_rect, track_color, true, -1.0, true)  # antialiased corners
	# Draw rounded caps (circles at each end)
	draw_circle(Vector2(track_rect.position.x, cy), radius, track_color)
	draw_circle(Vector2(track_rect.end.x, cy), radius, track_color)

	# Fill area (left portion up to grabber position, pill-shaped)
	var ratio = 0.0
	if max_value > min_value:
		ratio = (value - min_value) / (max_value - min_value)

	var fill_end_x = margin + ratio * (size.x - _grabber_width)
	var fill_width = fill_end_x - margin

	if fill_width > 0.01:
		var fill_rect = Rect2(margin, cy - radius, fill_width, track_height)
		draw_rect(fill_rect, fill_color, true, -1.0, true)
		# Left cap
		draw_circle(Vector2(fill_rect.position.x, cy), radius, fill_color)
		# Right cap
		draw_circle(Vector2(fill_rect.end.x, cy), radius, fill_color)

func _update_sprite() -> void:
	if not is_instance_valid(_sprite): return

	var ratio = 0.0
	if max_value > min_value:
		ratio = (value - min_value) / (max_value - min_value)

	var available_width = size.x - _grabber_width
	var center_x = (_grabber_width / 2.0) + (ratio * available_width)
	var center_y = size.y / 2.0

	_sprite.position = Vector2(center_x, center_y)
	_sprite.rotation = ratio * rotation_speed * 2 * PI
