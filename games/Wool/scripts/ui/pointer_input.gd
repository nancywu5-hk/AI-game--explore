class_name PointerInput
extends RefCounted

## Pointer input that counts one physical press once, mouse or finger alike.
##
## The game keeps emulate_mouse_from_touch on (Godot's default) so it can be
## played with either. The cost is that a single tap arrives twice: once as the
## real InputEventScreenTouch, and again as an InputEventMouseButton synthesised
## from it. Anything acting on "a press" therefore fires twice per tap - which is
## what made one tap on the game over screen skip the animation *and* restart.
##
## Godot stamps every synthesised event with device == DEVICE_ID_EMULATION (-1),
## while real devices report >= 0. Dropping the emulated half is exact - no
## timing windows, no debounce - and leaves a real mouse and a real finger both
## fully working.

## The synthetic half of a tap (or of a click, if emulate_touch_from_mouse is
## ever enabled). Checked only for pointer events: keyboards and gamepads report
## device ids that must not be filtered this way.
static func is_emulated(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.device == InputEvent.DEVICE_ID_EMULATION
	return false

## True exactly once per physical tap or left click.
static func is_pointer_press(event: InputEvent) -> bool:
	if event.is_echo() or is_emulated(event):
		return false

	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.pressed and button.button_index == MOUSE_BUTTON_LEFT

	return false

## True exactly once per press from any input device - pointer, key or gamepad.
## For "tap anywhere to continue" screens.
static func is_any_press(event: InputEvent) -> bool:
	if is_pointer_press(event):
		return true
	if event.is_echo() or is_emulated(event):
		return false

	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed

	return false

## Screen position of a pointer event; Vector2.ZERO for anything without one, so
## callers doing a rect test should pair this with is_pointer_press().
static func press_position(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return Vector2.ZERO
