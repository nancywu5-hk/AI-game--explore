class_name BaseLevel
extends Node2D

## Base class for all levels
##
## Manages level-specific logic and spawn points.

# === PUBLIC METHODS ===

## Get the player spawn point position
func get_player_spawn_point() -> Vector2:
	var spawn_point: Node2D = get_node_or_null("SpawnPoint")
	if spawn_point:
		return spawn_point.global_position

	push_warning("No 'SpawnPoint' node found in level. Returning (0,0).")
	return Vector2.ZERO
