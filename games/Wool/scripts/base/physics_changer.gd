## PhysicsChanger - Abstract Base Class
##
## This is the base interface for all components that can modify character physics.
## Both Features (wings, grappling, etc.) and Terrains (underwater, ice, etc.) inherit from this.
##
## The Character iterates over all PhysicsChangers and calls get_movement_factor()
## to calculate the final physics vector for movement.
class_name PhysicsChanger
extends Node2D

## Virtual method - MUST be overridden by child classes
## Returns a Vector2 that modifies the character's movement
## @param delta: The physics delta time
## @param character_position: The current position of the character
## @return Vector2: The movement factor to apply
func get_movement_factor(_delta: float, _character_position: Vector2) -> Vector2:
	push_error("PhysicsChanger.get_movement_factor() must be overridden in child class: " + get_script().resource_path)
	return Vector2.ZERO

## Virtual method - Called when the PhysicsChanger is activated
func activate() -> void:
	pass

## Virtual method - Called when the PhysicsChanger is deactivated
func deactivate() -> void:
	pass

## Check if this PhysicsChanger is currently active
func is_active() -> bool:
	return true  # Default: always active, override if needed
