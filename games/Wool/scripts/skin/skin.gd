## BodySkin - Character Visual Component
##
## Manages the visual representation of a character.
## Consists of multiple body parts (Head, Body, Feet, etc.)
## Each part has its own sprite and hitbox.
##
## This allows for modular character visuals and body-part-specific interactions.
## Note: Renamed from "Skin" to avoid conflict with Godot's native Skin class
class_name BodySkin
extends Node2D

# === SIGNALS ===
signal skin_changed()

# === EXPORTED VARIABLES ===
@export var skin_name: String = "DefaultSkin"

# === ONREADY VARIABLES ===
@onready var head: Node2D = $Head if has_node("Head") else null
@onready var body: Node2D = $Body if has_node("Body") else null
@onready var feet: Node2D = $Feet if has_node("Feet") else null
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else ($Body/AnimatedSprite2D if has_node("Body/AnimatedSprite2D") else null)

# === BUILT-IN METHODS ===
func _ready() -> void:
	_setup_skin()

# === PUBLIC METHODS ===

## Play an animation if AnimatedSprite2D is present
func play_animation(animation_name: String) -> void:
	if animated_sprite:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.play(animation_name)
		else:
			# Fallback logic to prevent spam
			if (animation_name == "default" or animation_name == "idle") and animated_sprite.sprite_frames.has_animation("walk"):
				animated_sprite.play("walk")
			elif animated_sprite.sprite_frames.get_animation_names().size() > 0:
				# Play the first available animation as generic fallback
				var first_anim = animated_sprite.sprite_frames.get_animation_names()[0]
				animated_sprite.play(first_anim)
			else:
				push_warning("Animation '%s' not found in skin '%s'" % [animation_name, skin_name])
	else:
		push_warning("No AnimatedSprite2D found in skin '%s'" % skin_name)

## Get the sprite of a specific body part
func get_body_part_sprite(part_name: String) -> Sprite2D:
	var part: Node2D = get_node_or_null(part_name)
	if part and part.has_node("Sprite2D"):
		return part.get_node("Sprite2D")
	return null

## Get the hitbox of a specific body part
func get_body_part_hitbox(part_name: String) -> CollisionShape2D:
	var part: Node2D = get_node_or_null(part_name)
	if part and part.has_node("Hitbox"):
		return part.get_node("Hitbox")
	return null

## Change the sprite of a specific body part
func set_body_part_sprite(part_name: String, texture: Texture2D) -> void:
	var sprite: Sprite2D = get_body_part_sprite(part_name)
	if sprite:
		sprite.texture = texture
		skin_changed.emit()

## Set the main texture for the body
func set_texture(texture: Texture2D) -> void:
	set_body_part_sprite("Body", texture)

## Show/hide a specific body part
func set_body_part_visible(part_name: String, visible_state: bool) -> void:
	var part: Node2D = get_node_or_null(part_name)
	if part:
		part.visible = visible_state

## Get all body parts
func get_all_body_parts() -> Array[Node2D]:
	var parts: Array[Node2D] = []
	for child in get_children():
		if child is Node2D:
			parts.append(child)
	return parts

# === VIRTUAL METHODS (Override in child classes) ===

## Override for custom skin setup
func _setup_skin() -> void:
	pass
