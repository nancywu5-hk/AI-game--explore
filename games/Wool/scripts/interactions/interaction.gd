## Interaction - Abstract Base Class
##
## Base class for all interactive objects (Nail, Box, etc.)
## Interactions are objects that characters can interact with.
##
## Interactions notify the character when they enter/exit range,
## and the character decides whether to activate corresponding features.
class_name Interaction
extends Area2D

# === SIGNALS ===
signal character_in_range(character: CharacterBody2D, interaction: Interaction)
signal character_out_of_range(character: CharacterBody2D, interaction: Interaction)
signal interaction_used(character: CharacterBody2D)

# === EXPORTED VARIABLES ===
@export var interaction_name: String = "UnnamedInteraction"
@export var is_active: bool = true
@export var highlight_on_range: bool = true
@export var prompt_action: String = "" # Input action name (e.g. "interact")
@export var prompt_text: String = ""   # Text to display (e.g. "Cut")

# === PUBLIC VARIABLES ===
var highlight_color: Color
var normal_color: Color
var prompt_label: Label

# === PRIVATE VARIABLES ===
var _characters_in_range: Array[CharacterBody2D] = []
var _is_being_used: bool = false

# === ONREADY VARIABLES ===
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

# === BUILT-IN METHODS ===
func _ready() -> void:
	add_to_group("interactions")
	_setup_prompt_label()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if sprite:
		sprite.modulate = normal_color

	_setup_tweakables()
	_setup_interaction()

func _setup_prompt_label() -> void:
	if prompt_action == "" and prompt_text == "":
		return

	prompt_label = Label.new()
	prompt_label.visible = false
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	prompt_label.position = Vector2(-50, -80) # Above the object
	prompt_label.size = Vector2(100, 30)
	prompt_label.z_index = 100 # On top
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 4)
	add_child(prompt_label)

	_update_prompt_text()

func _update_prompt_text() -> void:
	if not prompt_label:
		return

	var key_text: String = ""
	if prompt_action != "":
		var events = InputMap.action_get_events(prompt_action)
		if events.size() > 0:
			key_text = events[0].as_text().split(" ")[0] # Get first key (e.g. "F")

	if key_text != "":
		prompt_label.text = "Press %s to %s" % [key_text, prompt_text]
	else:
		prompt_label.text = prompt_text

# === PUBLIC METHODS ===

## Setup tweakables
func _setup_tweakables() -> void:
	highlight_color = InteractionConstants.get_value("Visuals", "highlight_nail_color", Color(1.5, 1.5, 1.5, 1.0))
	normal_color = InteractionConstants.get_value("Visuals", "nail_color", Color(1.0, 1.0, 1.0, 1.0))

	if not InteractionConstants.value_changed.is_connected(_on_tweakable_changed):
		InteractionConstants.value_changed.connect(_on_tweakable_changed)

	_update_visual()

func _on_tweakable_changed(category: String, key: String, value: Variant) -> void:
	if category == "Visuals":
		match key:
			"highlight_nail_color":
				highlight_color = value
				_update_visual()
			"nail_color":
				normal_color = value
				_update_visual()
			"rusty_nail_color":
				# For rusty nails, but since this is base, maybe ignore or handle in subclass
				pass

## Check if a specific character is in range
func is_character_in_range(character: CharacterBody2D) -> bool:
	return character in _characters_in_range

## Get all characters currently in range
func get_characters_in_range() -> Array[CharacterBody2D]:
	return _characters_in_range.duplicate()

## Mark interaction as being used
func set_used(used: bool) -> void:
	_is_being_used = used
	_update_visual()

## Check if interaction is currently being used
func is_being_used() -> bool:
	return _is_being_used

# === VIRTUAL METHODS (Override in child classes) ===

## Override for custom setup logic
func _setup_interaction() -> void:
	pass

## Called when a character enters interaction range
func _on_character_entered(character: CharacterBody2D) -> void:
	if prompt_label:
		prompt_label.visible = true

## Called when a character exits interaction range
func _on_character_exited(character: CharacterBody2D) -> void:
	if prompt_label:
		prompt_label.visible = false

## Called when interaction is used by a character
func _on_interaction_used(character: CharacterBody2D) -> void:
	pass

## Get the interaction point (e.g., grapple point for nail)
## Override in child classes for custom interaction points
func get_interaction_point() -> Vector2:
	return global_position

# === PRIVATE METHODS ===
func _update_visual() -> void:
	if not sprite or not highlight_on_range:
		return

	if _characters_in_range.size() > 0 and not _is_being_used:
		sprite.modulate = highlight_color
	else:
		sprite.modulate = normal_color

# === SIGNAL CALLBACKS ===
func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return

	if body is CharacterBody2D:
		_characters_in_range.append(body)
		_update_visual()
		_on_character_entered(body)
		character_in_range.emit(body, self)

		# Direct registration with character (more robust than scene tree search)
		if body.has_method("add_nearby_interaction"):
			body.add_nearby_interaction(self)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_characters_in_range.erase(body)
		_update_visual()
		_on_character_exited(body)
		character_out_of_range.emit(body, self)

		# Direct deregistration
		if body.has_method("remove_nearby_interaction"):
			body.remove_nearby_interaction(self)
