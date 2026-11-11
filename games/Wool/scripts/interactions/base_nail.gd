class_name BaseNail
extends Interaction

## Base Class for all Nails (Normal, Rusty, etc.)
## Defines standardized structure:
## - GrapplePoint (Marker2D)
## - Back Sprite (z_index = -1)
## - Front Sprite (z_index = 1)
## - Detection Radius

@export var grapple_point_offset: Vector2 = Vector2.ZERO

# Standardized Child Node Names
const NODE_BACK_SPRITE = "BackSprite"
const NODE_FRONT_SPRITE = "FrontSprite"
const NODE_GRAPPLE_POINT = "GrapplePoint"
const NODE_SHADOW_SPRITE = "ShadowSprite"

# === HIGHLIGHTING LOGIC ===
# Store initial modulations per node instance to handle diverse base colors correctly
var _initial_modulations: Dictionary = {}
var _is_highlighted: bool = false
var _highlight_halo: Sprite2D = null
var _highlight_tween: Tween = null

func _ready() -> void:
	super._ready()
	_enforce_z_ordering()
	_store_initial_modulations()
	_create_highlight_sprite()
	add_to_group("nails")

func _store_initial_modulations() -> void:
	var nodes = [get_node_or_null(NODE_FRONT_SPRITE), get_node_or_null(NODE_BACK_SPRITE)]
	for node in nodes:
		if node and node is CanvasItem:
			_initial_modulations[node] = node.modulate

## Every nail's halo is the same 256x256 radial fade, so it is built once and
## shared by all of them. Building it per instance cost a CPU gradient fill plus
## a GPU upload for each of the ~60-80 nails alive at a time - paid mid-run
## whenever a pool ran dry, which is exactly when a hitch is most visible.
## Nothing mutates the texture per nail; tint and pulse live on the Sprite2D.
static var _shared_halo_texture: GradientTexture2D = null

static func _get_halo_texture() -> GradientTexture2D:
	if _shared_halo_texture:
		return _shared_halo_texture

	# Procedural Gradient Texture
	var gradient = Gradient.new()
	# Use WHITE gradient so that modulate (tint) works correctly with any color.
	# Core: White
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	# Edge: Transparent White
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0) # Radius 0.5
	texture.width = 256
	texture.height = 256

	_shared_halo_texture = texture
	return _shared_halo_texture

func _create_highlight_sprite() -> void:
	if _highlight_halo: return

	_highlight_halo = Sprite2D.new()
	_highlight_halo.name = "HighlightHalo"

	_highlight_halo.texture = _get_halo_texture()
	_highlight_halo.visible = false
	_highlight_halo.z_index = -1 # Behind nail (0), in front of shadow (-2)
	_highlight_halo.modulate = Color("#ffffff")

	add_child(_highlight_halo)

func set_highlight(active: bool) -> void:
	if _is_highlighted == active:
		return

	_is_highlighted = active

	# Nodes modulation removed to avoid washout. Using only Halo.

	if active:
		# Show and Pulse Halo
		if _highlight_halo:
			_highlight_halo.visible = true
			_start_pulse_animation()

	else:
		# Hide Halo
		if _highlight_halo:
			_highlight_halo.visible = false
			if _highlight_tween:
				_highlight_tween.kill()

func _start_pulse_animation() -> void:
	if _highlight_tween:
		_highlight_tween.kill()

	_highlight_tween = create_tween().set_loops()
	# Pulse Scale: 1.0 -> 1.2 -> 1.0
	_highlight_tween.tween_property(_highlight_halo, "scale", Vector2(0.8, 0.8), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_highlight_tween.tween_property(_highlight_halo, "scale", Vector2(0.5, 0.5), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Restore a pooled nail to its as-spawned state.
##
## Pooling reuses the node, so anything the previous life left behind - the
## highlight halo, the "in use" flag, a stale character in _characters_in_range
## because the body_exited signal never arrived while the node sat parked
## offscreen - would otherwise leak into the next spawn. Subclasses override
## this and call super() to add their own state.
func reset() -> void:
	set_highlight(false)
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null

	_characters_in_range.clear()
	is_active = true
	set_used(false)
	rotation = 0.0
	_update_visual()

func _setup_interaction() -> void:
	interaction_name = "BaseNail"
	# Default visual update
	_update_visual()

func _enforce_z_ordering() -> void:
	# Ensure standard layering for player interaction
	var back = get_node_or_null(NODE_BACK_SPRITE)
	if back:
		back.z_index = 0 # Base Layer

	var front = get_node_or_null(NODE_FRONT_SPRITE)
	if front:
		front.z_index = 2 # Top Layer

	var shadow = get_node_or_null(NODE_SHADOW_SPRITE)
	if shadow:
		shadow.z_index = -2 # Background Shadow Layer (Behind Pickaxe Shadow -1)

	# Wool's pickaxe uses Z-Index 1 to sit between them.

func get_grapple_point() -> Vector2:
	return global_position + grapple_point_offset

## Get the effective detection radius
func get_detection_radius() -> float:
	# Try to find the collision shape by name first
	var collision_shape = get_node_or_null("CollisionShape2D")

	# If not found or not a circle, search children
	if not collision_shape or not (collision_shape.shape is CircleShape2D):
		for child in get_children():
			if child is CollisionShape2D and child.shape is CircleShape2D:
				collision_shape = child
				break

	if collision_shape and collision_shape.shape is CircleShape2D:
		# Use the global scale of the collision shape itself to account for all parent scaling AND its own scaling
		var shape_scale = collision_shape.global_scale
		var max_scale = max(abs(shape_scale.x), abs(shape_scale.y))
		return collision_shape.shape.radius * max_scale

	# Fallback
	return 100.0

# Virtual method for visual updates
func _update_visual() -> void:
	pass

func get_boost_multiplier() -> float:
	return 1.0


