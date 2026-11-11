## BaseEnemy - Base class for all enemy characters
##
## Inherits from BaseCharacter and adds enemy-specific functionality:
## - AI behavior
## - Attack logic
## - Targeting system
##
## Specific enemy types (Bunny, Slime, etc.) inherit from this.
class_name BaseEnemy
extends BaseCharacter

# === SIGNALS ===
signal target_acquired(target: Node2D)
signal target_lost()
signal despawn_requested(node: Node)

# === EXPORTED VARIABLES ===
# Removed exports in favor of Tweakables

# === PUBLIC VARIABLES ===
var jump_velocity: float = -400.0

# === PRIVATE VARIABLES ===
var _current_target: Node2D = null


var _spawn_position: Vector2
var _shadow_sprite: AnimatedSprite2D

# === ENUMS ===

# === ONREADY VARIABLES ===

# === BUILT-IN METHODS ===
func _ready() -> void:
	_spawn_position = global_position
	# Ensure enemies render above Nails (Z=0 and Z=2)
	z_index = 10

	# Disable collision with other enemies (remove own layer from mask)
	collision_mask &= ~collision_layer

	# Create Shadow
	_shadow_sprite = AnimatedSprite2D.new()
	_shadow_sprite.name = "ShadowSprite"
	_shadow_sprite.modulate = Color(0, 0, 0, 0.5)
	_shadow_sprite.z_index = -12
	add_child(_shadow_sprite)
	# Move to back of children list to be safe, though Z-index handles drawing
	move_child(_shadow_sprite, 0)

	super._ready()


	if hitbox_area:
		if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox_area.body_entered.connect(_on_hitbox_body_entered)

	GameManager.state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.GAME_OVER:
		set_physics_process(false)
		set_process(false)
		if _shadow_sprite:
			_shadow_sprite.visible = false


# === PUBLIC METHODS ===

func reset() -> void:
	velocity = Vector2.ZERO
	rotation = 0
	process_mode = Node.PROCESS_MODE_INHERIT

func show_spawn_warning() -> void:
	# Add warning icon
	var warning_scene = preload("res://scenes/ui/warn_player.tscn")
	var warning_instance = warning_scene.instantiate()

	# Needs to be added to a CanvasLayer (HUD) to stick to screen
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_child(warning_instance)
		# Configure warning
		if "target" in warning_instance:
			warning_instance.target = self
	else:
		# Fallback if no HUD found (testing?) - attach to self but it won't clamp correctly
		add_child(warning_instance)

func die() -> void:
	# Drop features if any

	# Play death animation if available (TODO)
	# Play death animation if available (TODO)
	despawn_requested.emit(self)
	set_physics_process(false)

	# Update Shadow
	# Update Shadow - Logic moved to _process

func _process(delta: float) -> void:
	# Cleanup if too far behind player
	# We use a large buffer to ensure we don't despot eagles that are swooping
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		# If we are more than 3000px behind the player, we are definitely off screen and safe to remove
		if global_position.x < player.global_position.x - 3000.0:
			despawn_requested.emit(self)

	# Update Shadow
	if _shadow_sprite and skin:
		# Find the main animated sprite/sprite inside skin
		# Skin is BodySkin class usually, which has `animated_sprite`
		var main_sprite = null
		if "animated_sprite" in skin:
			main_sprite = skin.animated_sprite

		if main_sprite:
			_shadow_sprite.sprite_frames = main_sprite.sprite_frames
			_shadow_sprite.animation = main_sprite.animation
			_shadow_sprite.frame = main_sprite.frame
			_shadow_sprite.speed_scale = main_sprite.speed_scale
			_shadow_sprite.flip_h = main_sprite.flip_h
			_shadow_sprite.flip_v = main_sprite.flip_v
			# The shadow is a sibling of Skin, so it must also pick up the inner
			# sprite's own scale, which compensates for the downscaled atlas.
			_shadow_sprite.scale = skin.scale * main_sprite.scale
			_shadow_sprite.rotation = skin.rotation
			_shadow_sprite.offset = main_sprite.offset
			_shadow_sprite.centered = main_sprite.centered

			# Position Offset
			# If Enemy is scaled 0.1, we need 100 px offset to get 10px visual
			# Assuming enemies are generally scaled similarly to Wool (0.1)
			# Better: Check scale?
			# BaseCharacter doesn't strictly enforce scale. But Fish.tscn has scale 0.1.
			# Let's use constant offset vector (100, 100) as per Wool
			_shadow_sprite.position = skin.position + Vector2(100, 100)

func _process_physics(delta: float) -> void:
	_process_ai(delta)
	super._process_physics(delta)

func _process_ai(delta: float) -> void:
	pass


# === PRIVATE METHODS ===

const FRICTION: float = 1200.0



# === SIGNAL CALLBACKS ===


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is BasePlayer:
		body.take_damage(body.max_health)
