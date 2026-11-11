extends CanvasLayer

## First-launch name prompt, shown once per install.
##
## The game boots straight into level_1 with no menu in front of it, so this is
## the only place there is to ask. level_1 opens it when LeaderboardManager has
## no stored name; nothing clears that name afterwards, so it never returns.
##
## Follows settings_window.gd: same close_requested handshake with UIManager,
## same clampf-based responsive layout. It deliberately breaks with it in two
## ways, both because a name is required rather than optional - the close button
## is hidden, and tapping outside the panel does nothing.

## Emitted once a name is stored. UIManager does the actual closing - see the
## "windows never close themselves" rule in ui_manager.gd.
signal close_requested

@onready var panel: Control = $Control/OuterMargin/CenterContainer/Panel
@onready var content_margin: MarginContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin
@onready var container: VBoxContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/VBoxContainer
@onready var title_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/VBoxContainer/TitleLabel
@onready var hint_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/VBoxContainer/HintLabel
@onready var name_edit: LineEdit = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/VBoxContainer/NameEdit
@onready var confirm_button: Button = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/VBoxContainer/ConfirmButton

## What the field was pre-filled with, so an emptied field still has something to
## store.
var _suggested: String = ""

func _ready() -> void:
	# There is no way past this window other than confirming: the player has to
	# leave with a name, and every downstream screen is written assuming they did.
	var close_button := get_node_or_null(
		"Control/OuterMargin/CenterContainer/Panel/MenuBackground/CloseButton"
	) as Button
	if close_button:
		close_button.visible = false

	# Pre-filled rather than empty: the player owes us a name, not typing. One tap
	# on the button is a complete answer.
	_suggested = LeaderboardManager.generate_name()
	name_edit.text = _suggested

	confirm_button.pressed.connect(_on_confirm_pressed)
	name_edit.text_submitted.connect(_on_name_submitted)

	get_tree().root.size_changed.connect(_update_layout)
	_update_layout.call_deferred()

## Enter in the field means the same as pressing the button below it.
func _on_name_submitted(_text: String) -> void:
	_on_confirm_pressed()

func _on_confirm_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)

	# Clearing the field is not a request to have no name - it is just an empty
	# field. Fall back to the suggestion they were given for free.
	var entered: String = LeaderboardEntry.sanitize_name(name_edit.text)
	LeaderboardManager.set_player_name(_suggested if entered.is_empty() else entered)

	# Nothing is published here. The name is local until the settings switch says
	# otherwise, so first launch asks for an identity, never for consent.
	close_requested.emit()

func _update_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size: float = minf(viewport_size.x, viewport_size.y)

	var inner_margin_x: float = clampf(viewport_size.x * 0.05, 20.0, 160.0)
	var inner_margin_y: float = clampf(viewport_size.y * 0.05, 20.0, 80.0)
	content_margin.add_theme_constant_override("margin_left", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_top", int(inner_margin_y))
	content_margin.add_theme_constant_override("margin_right", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_bottom", int(inner_margin_y))
	container.add_theme_constant_override(
		"separation", int(clampf(viewport_size.y * 0.03, 16.0, 40.0))
	)

	title_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.07, 34.0, 90.0)))
	hint_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.03, 18.0, 36.0)))

	name_edit.add_theme_font_size_override("font_size", int(clampf(base_size * 0.038, 24.0, 48.0)))
	# Width only - the styled box brings its own vertical padding, so forcing a
	# height here would crop the text.
	name_edit.custom_minimum_size = Vector2(clampf(viewport_size.x * 0.3, 240.0, 480.0), 0.0)

	confirm_button.add_theme_font_size_override(
		"font_size", int(clampf(base_size * 0.04, 22.0, 48.0))
	)
	confirm_button.custom_minimum_size = Vector2(
		clampf(viewport_size.x * 0.28, 220.0, 380.0),
		clampf(base_size * 0.085, 56.0, 96.0)
	)
