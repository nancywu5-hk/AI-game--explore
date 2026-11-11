extends CanvasLayer

## "Enjoying Wool?" popup. Owned by ReviewManager, which decides when it may
## appear at all - this script only reports which button was pressed.
##
## Not a UIManager window on purpose: it has to sit above the game over screen's
## own CanvasLayer (layer 200), and UIManager pauses the tree, which would
## freeze the game over screen underneath it.

signal close_requested

@onready var panel: Control = $Control/OuterMargin/CenterContainer/Panel
@onready var rate_button: Button = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/Buttons/RateButton
@onready var later_button: Button = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/Buttons/LaterButton
@onready var title_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/TitleLabel
@onready var body_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/BodyLabel

func _ready() -> void:
	rate_button.pressed.connect(_on_rate_pressed)
	later_button.pressed.connect(_on_later_pressed)

	var close_button := get_node_or_null(
		"Control/OuterMargin/CenterContainer/Panel/MenuBackground/CloseButton"
	) as Button
	if close_button:
		# Dismissing with the X means the same thing as "Later".
		close_button.pressed.connect(_on_later_pressed)

	get_tree().root.size_changed.connect(_update_layout)
	_update_layout.call_deferred()

func _on_rate_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	ReviewManager.accept()
	close_requested.emit()

func _on_later_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	ReviewManager.decline()
	close_requested.emit()

## Same clampf-based responsive sizing the other windows use.
func _update_layout() -> void:
	if not is_instance_valid(panel):
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size: float = minf(viewport_size.x, viewport_size.y)

	panel.custom_minimum_size = Vector2(clampf(viewport_size.x * 0.6, 520.0, 900.0), 0.0)

	title_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.075, 36.0, 88.0)))
	body_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.042, 24.0, 48.0)))

	var button_size := Vector2(
		clampf(viewport_size.x * 0.22, 180.0, 340.0),
		clampf(base_size * 0.11, 56.0, 96.0)
	)
	var button_font_size: int = int(clampf(base_size * 0.05, 26.0, 56.0))
	for button in [rate_button, later_button]:
		button.custom_minimum_size = button_size
		button.add_theme_font_size_override("font_size", button_font_size)
