extends Node

## UIManager - the modal window stack.
##
## Exactly one window is on screen at a time: opening a window hides the one it
## was opened from, closing it reveals that window again. This autoload is the
## single owner of get_tree().paused - no window and no other script writes it.

signal stack_changed(depth: int)

## Layers are handed out bottom-up so a window can never end up drawn behind the
## window that opened it, and so the scrim is always underneath both.
const SCRIM_LAYER: int = 90
const BASE_LAYER: int = 100
const LAYER_STEP: int = 10
## Lifted from the pause menu's ColorRect - the other windows never had a dimmer
## of their own and relied on the pause menu supplying one.
const SCRIM_COLOR: Color = Color(0.4392157, 0.40784314, 0.5294118, 0.6862745)

const WINDOW_SCENES: Dictionary = {
	&"pause": preload("res://scenes/ui/pause_menu.tscn"),
	&"settings": preload("res://scenes/ui/settings_window.tscn"),
	&"leaderboard": preload("res://scenes/ui/leaderboard_window.tscn"),
	&"credits": preload("res://scenes/ui/credits.tscn"),
	&"username": preload("res://scenes/ui/username_prompt.tscn"),
}

## Windows kept alive (hidden) between opens. Credits is deliberately absent: it
## scrolls from a position computed at _ready, so it must be rebuilt each time.
## So is username: it opens once per install and never again.
const CACHED_WINDOWS: Array[StringName] = [&"pause", &"settings", &"leaderboard"]

## Entries are {id, node, host}. "node" carries the window script; "host" is the
## node itself when the scene is already a CanvasLayer, and a wrapper otherwise
## (credits is Control-rooted).
var _stack: Array[Dictionary] = []
var _cache: Dictionary = {}
var _scrim: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scrim()

# === PUBLIC API ===

func open(id: StringName) -> Node:
	# Re-opening the window already on screen is a no-op, not a second entry.
	if is_open(id):
		return get_window_node(id)

	var entry: Dictionary = _acquire(id)
	if entry.is_empty():
		push_error("UIManager: unknown window id '%s'" % id)
		return null

	if not _stack.is_empty():
		(_stack.back()["host"] as CanvasLayer).visible = false

	_stack.append(entry)
	_apply_layers()
	_show_entry(entry, true)
	_after_stack_changed()
	return entry["node"]

## Close the topmost window and reveal whatever opened it.
func close_top() -> void:
	if not _stack.is_empty():
		close(_stack.back()["id"])

func close(id: StringName) -> void:
	var index: int = _index_of(id)
	if index == -1:
		return

	var was_on_screen: bool = index == _stack.size() - 1
	var entry: Dictionary = _stack[index]
	_stack.remove_at(index)
	_release(entry)
	_apply_layers()

	# Only the window that was actually visible needs a replacement.
	if was_on_screen and not _stack.is_empty():
		_show_entry(_stack.back(), false)

	_after_stack_changed()

func close_all() -> void:
	while not _stack.is_empty():
		_release(_stack.pop_back())
	# Runs unconditionally: callers such as GameManager.start_game() use this as
	# their "guarantee the tree is unpaused" call.
	_after_stack_changed()

func is_open(id: StringName) -> bool:
	return _index_of(id) != -1

func get_depth() -> int:
	return _stack.size()

func get_top_id() -> StringName:
	return _stack.back()["id"] if not _stack.is_empty() else &""

## Not named get_window(): that would shadow Node.get_window() -> Window.
func get_window_node(id: StringName) -> Node:
	var index: int = _index_of(id)
	return _stack[index]["node"] if index != -1 else null

# === PRIVATE METHODS ===

func _index_of(id: StringName) -> int:
	for i in _stack.size():
		if _stack[i]["id"] == id:
			return i
	return -1

## Reuses a cached instance when there is one, otherwise instantiates and - for
## Control-rooted scenes such as credits - wraps it in a CanvasLayer, so every
## entry can be shown, hidden and z-ordered through one code path.
func _acquire(id: StringName) -> Dictionary:
	if _cache.has(id):
		var cached: Dictionary = _cache[id]
		if is_instance_valid(cached["node"]):
			return cached
		_cache.erase(id)

	if not WINDOW_SCENES.has(id):
		return {}

	var node: Node = (WINDOW_SCENES[id] as PackedScene).instantiate()
	var host: CanvasLayer

	if node is CanvasLayer:
		host = node as CanvasLayer
	else:
		host = CanvasLayer.new()
		host.name = "%sHost" % id
		host.process_mode = Node.PROCESS_MODE_ALWAYS
		host.add_child(node)

	host.visible = false
	get_tree().root.add_child(host)

	if node.has_signal("close_requested"):
		node.close_requested.connect(_on_close_requested.bind(id))

	var entry: Dictionary = {"id": id, "node": node, "host": host}
	if CACHED_WINDOWS.has(id):
		_cache[id] = entry
	return entry

## is_fresh distinguishes "pushed onto the stack" from "revealed again because
## the window above it closed" - the leaderboard reloads on the first, not the
## second.
func _show_entry(entry: Dictionary, is_fresh: bool) -> void:
	(entry["host"] as CanvasLayer).visible = true
	var node: Node = entry["node"]
	if is_fresh:
		if node.has_method("on_opened"):
			node.on_opened()
	elif node.has_method("on_revealed"):
		node.on_revealed()

func _release(entry: Dictionary) -> void:
	var node: Node = entry["node"]
	if node.has_method("on_closed"):
		node.on_closed()

	var host: CanvasLayer = entry["host"]
	host.visible = false
	if not _cache.has(entry["id"]):
		host.queue_free()

func _apply_layers() -> void:
	for i in _stack.size():
		(_stack[i]["host"] as CanvasLayer).layer = BASE_LAYER + LAYER_STEP * i

func _after_stack_changed() -> void:
	var depth: int = _stack.size()
	if _scrim:
		_scrim.visible = depth > 0
	get_tree().paused = depth > 0
	if depth == 0:
		# The tap that dismissed the last window must not also reach gameplay
		# and register as a jump.
		GameManager.ignore_input_for(0.15)
	stack_changed.emit(depth)

func _on_close_requested(id: StringName) -> void:
	close(id)

## One shared dimmer for every window. Previously only the pause menu had one,
## which is why hiding it would leave the others over undimmed gameplay.
func _build_scrim() -> void:
	_scrim = CanvasLayer.new()
	_scrim.name = "UIScrim"
	_scrim.layer = SCRIM_LAYER
	_scrim.visible = false

	var rect := ColorRect.new()
	rect.color = SCRIM_COLOR
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The window on top owns every tap; the scrim must never intercept one.
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.add_child(rect)

	# Deferred: root is still assembling its own children during autoload _ready.
	get_tree().root.add_child.call_deferred(_scrim)
