class_name SpitProjectile
extends Area2D

@export var speed: float = 600.0
@export var projectile_gravity: float = 900.0
@export var rotation_speed: float = 360.0

var velocity: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.UP

func _ready() -> void:
	# Initial velocity based on direction and speed
	# Plant shoots UP, so direction is (0, -1)
	velocity = direction * speed

	body_entered.connect(_on_body_entered)

	# Auto despawn if alive too long (safety)
	# Auto despawn if alive too long (safety)
	get_tree().create_timer(5.0).timeout.connect(queue_free)

	if has_node("Shadow"):
		$Shadow.top_level = true

func _process(delta: float) -> void:
	# Apply gravity
	velocity.y += projectile_gravity * delta

	# Move
	position += velocity * delta

	# Rotate visuals
	rotation_degrees += rotation_speed * delta

	# Update Shadow
	if has_node("Shadow"):
		$Shadow.global_position = global_position + Vector2(20, 20)
		$Shadow.global_rotation = global_rotation
		$Shadow.global_scale = global_scale

	# Despawn if too high
	if global_position.y < -2048.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body is BasePlayer:
		body.take_damage(body.max_health)
		queue_free()
	elif body.name == "Left Border":
		queue_free()
