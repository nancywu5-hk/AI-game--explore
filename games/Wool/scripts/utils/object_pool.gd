class_name ObjectPool
extends Node

## Generic Object Pool
## Manages a pool of nodes to avoid instantiation/destruction overhead.

var _scene: PackedScene
var _parent: Node
var _pool: Array[Node] = []
var _active_nodes: Array[Node] = []

func _init(scene: PackedScene, parent: Node, initial_size: int = 10) -> void:
	_scene = scene
	_parent = parent

	for i in range(initial_size):
		var node = _create_new_node()
		_release_node_to_pool(node)

func acquire() -> Node:
	var node: Node
	if _pool.is_empty():
		node = _create_new_node()
	else:
		node = _pool.pop_back()

	_active_nodes.append(node)

	if node is Node2D:
		node.visible = true
		node.process_mode = Node.PROCESS_MODE_INHERIT

	return node

func release(node: Node) -> void:
	# One scan, not two: `in` followed by erase() walked the array twice.
	var idx := _active_nodes.find(node)
	if idx == -1:
		return
	_active_nodes.remove_at(idx)
	_release_node_to_pool(node)

func _create_new_node() -> Node:
	if not _scene:
		return null

	var node = _scene.instantiate()
	if not node:
		return null

	if _parent:
		_parent.add_child(node)
	return node

func _release_node_to_pool(node: Node) -> void:
	if node is Node2D:
		node.visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
		# Reset position to avoid interference?
		node.position = Vector2(-9999, -9999)

	_pool.append(node)

# Cleanup all nodes (for level restart)
func reset() -> void:
	# Move all active nodes back to pool
	# Duplicate array to safely iterate while modifying
	var active_copy = _active_nodes.duplicate()
	for node in active_copy:
		release(node)
