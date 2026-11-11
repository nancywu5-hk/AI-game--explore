extends BaseMenu

@onready var settings_button: Button = $Control/OuterMargin/CenterContainer/MenuPanel/Content/VBoxContainer/SettingsButton
@onready var leaderboard_button: Button = $Control/OuterMargin/CenterContainer/MenuPanel/Content/VBoxContainer/LeaderboardButton
@onready var credits_button: Button = $Control/OuterMargin/CenterContainer/MenuPanel/Content/VBoxContainer/CreditsButton
@onready var menu_panel: Control = $Control/OuterMargin/CenterContainer/MenuPanel
@onready var pause_close_button: Button = $Control/OuterMargin/CenterContainer/MenuPanel/MenuBackground/CloseButton
@onready var root_control: Control = $Control
@onready var outer_margin: MarginContainer = $Control/OuterMargin
@onready var title_label: Label = $Control/OuterMargin/CenterContainer/MenuPanel/Content/Label

func _ready() -> void:
	super._ready()
	pause_close_button.pressed.connect(_on_resume_pressed)
	$Control.gui_input.connect(_on_overlay_gui_input)
	settings_button.pressed.connect(_on_settings_pressed)
	get_tree().root.size_changed.connect(_update_layout)

	# Buttons will use the textured theme from assets/ui/pause_theme.tres

	settings_button.text = "Settings"

	register_buttons([settings_button, leaderboard_button, credits_button], false, true)

	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	credits_button.pressed.connect(_on_credits_pressed)

	leaderboard_button.text = "Leaderboard"
	credits_button.text = "Credits"
	call_deferred("_update_layout")

func _update_layout() -> void:
	if root_control == null or outer_margin == null or menu_panel == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size: float = minf(viewport_size.x, viewport_size.y)

	# Keep margins flexible so the panel remains visible on narrow devices.
	var side_margin: float = clampf(viewport_size.x * 0.08, 12.0, 150.0)
	var vertical_margin: float = clampf(viewport_size.y * 0.08, 12.0, 150.0)
	outer_margin.add_theme_constant_override("margin_left", int(side_margin))
	outer_margin.add_theme_constant_override("margin_right", int(side_margin))
	outer_margin.add_theme_constant_override("margin_top", int(vertical_margin))
	outer_margin.add_theme_constant_override("margin_bottom", int(vertical_margin))

	var panel_available_width: float = maxf(viewport_size.x - side_margin * 2.0, 840.0)
	menu_panel.custom_minimum_size = Vector2(clampf(panel_available_width, 840.0, 1120.0), 0.0)

	if title_label:
		title_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.14, 48.0, 150.0)))
	if settings_button:
		settings_button.custom_minimum_size = Vector2(clampf(panel_available_width * 0.72, 180.0, 360.0), clampf(base_size * 0.12, 56.0, 96.0))
		settings_button.add_theme_font_size_override("font_size", int(clampf(base_size * 0.07, 36.0, 80.0)))
	if leaderboard_button:
		leaderboard_button.custom_minimum_size = Vector2(clampf(panel_available_width * 0.72, 180.0, 360.0), clampf(base_size * 0.12, 56.0, 96.0))
		leaderboard_button.add_theme_font_size_override("font_size", int(clampf(base_size * 0.07, 36.0, 80.0)))
	if credits_button:
		credits_button.custom_minimum_size = Vector2(clampf(panel_available_width * 0.72, 180.0, 360.0), clampf(base_size * 0.12, 56.0, 96.0))
		credits_button.add_theme_font_size_override("font_size", int(clampf(base_size * 0.07, 36.0, 80.0)))

func _on_overlay_gui_input(event: InputEvent) -> void:
	if not PointerInput.is_pointer_press(event):
		return

	var press: Vector2 = PointerInput.press_position(event)
	if menu_panel and not menu_panel.get_global_rect().has_point(press):
		_on_resume_pressed()

func _on_leaderboard_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	UIManager.open(&"leaderboard")

func _on_credits_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	UIManager.open(&"credits")

## Dismissing the pause menu empties the stack, which is what resumes the game -
## GameManager listens to UIManager.stack_changed for that.
func _on_resume_pressed() -> void:
	UIManager.close_all()
