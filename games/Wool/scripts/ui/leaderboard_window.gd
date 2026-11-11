extends CanvasLayer

## Global leaderboard overlay, opened from the pause menu via UIManager.
##
## Follows settings_window.gd: same close_requested handshake with the manager,
## same tap-outside-to-close overlay, same clampf-based responsive layout.

## Emitted when the user dismisses this window; UIManager does the closing.
signal close_requested

const ROW_SCENE: PackedScene = preload("res://scenes/ui/leaderboard_row.tscn")
const OWN_ROW_COLOR: Color = Color(0.44, 0.41, 0.53, 1)

@onready var root_control: Control = $Control
@onready var panel: Control = $Control/OuterMargin/CenterContainer/Panel
@onready var outer_margin: MarginContainer = $Control/OuterMargin
@onready var content_margin: MarginContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin
@onready var title_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/TitleLabel
@onready var status_label: Label = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/StatusLabel
@onready var scroll_container: ScrollContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/ScrollContainer
@onready var rows_container: VBoxContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/ScrollContainer/RowsContainer
@onready var own_rank_separator: HSeparator = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/OwnRankSeparator
@onready var own_rank_container: VBoxContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/OwnRankContainer
@onready var retry_button: Button = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/Content/RetryButton

func _ready() -> void:
	var close_button := get_node_or_null("Control/OuterMargin/CenterContainer/Panel/MenuBackground/CloseButton") as Button
	if close_button:
		close_button.pressed.connect(close)

	root_control.gui_input.connect(_on_overlay_gui_input)
	retry_button.pressed.connect(_on_retry_pressed)

	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	LeaderboardManager.top_updated.connect(_on_top_updated)
	LeaderboardManager.availability_changed.connect(_on_availability_changed)

	get_tree().root.size_changed.connect(_update_layout)
	_update_layout.call_deferred()

## Called by UIManager when this window is pushed onto the stack - not when it
## is revealed again after a window above it closed, so a sub-window does not
## trigger a redundant refetch.
func on_opened() -> void:
	_show_loading()
	LeaderboardManager.refresh_top()

## Asks UIManager to close this window; the manager owns visibility and pause.
func close() -> void:
	close_requested.emit()

## The connection came back while this window was open - fetch instead of
## leaving "Leaderboard unavailable" on screen until the player reopens it.
func _on_availability_changed(available: bool) -> void:
	if available and visible:
		_show_loading()
		LeaderboardManager.refresh_top(true)

func _update_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size: float = minf(viewport_size.x, viewport_size.y)

	var side_margin: float = clampf(viewport_size.x * 0.06, 16.0, 150.0)
	var vertical_margin: float = clampf(viewport_size.y * 0.06, 16.0, 120.0)
	outer_margin.add_theme_constant_override("margin_left", int(side_margin))
	outer_margin.add_theme_constant_override("margin_right", int(side_margin))
	outer_margin.add_theme_constant_override("margin_top", int(vertical_margin))
	outer_margin.add_theme_constant_override("margin_bottom", int(vertical_margin))

	var inner_margin_x: float = clampf(viewport_size.x * 0.05, 20.0, 160.0)
	var inner_margin_y: float = clampf(viewport_size.y * 0.04, 20.0, 60.0)
	content_margin.add_theme_constant_override("margin_left", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_right", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_top", int(inner_margin_y))
	content_margin.add_theme_constant_override("margin_bottom", int(inner_margin_y))

	var panel_width: float = clampf(viewport_size.x - side_margin * 2.0, 640.0, 1200.0)
	panel.custom_minimum_size = Vector2(panel_width, 0.0)

	title_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.09, 40.0, 110.0)))
	status_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.04, 22.0, 48.0)))
	retry_button.add_theme_font_size_override("font_size", int(clampf(base_size * 0.05, 26.0, 60.0)))
	retry_button.custom_minimum_size = Vector2(
		clampf(panel_width * 0.4, 200.0, 420.0),
		clampf(base_size * 0.1, 64.0, 110.0)
	)

	scroll_container.custom_minimum_size.y = clampf(viewport_size.y * 0.42, 220.0, 520.0)

	var row_font_size: int = int(clampf(base_size * 0.038, 20.0, 46.0))
	for row in rows_container.get_children():
		_apply_row_font(row as Control, row_font_size)
	for row in own_rank_container.get_children():
		_apply_row_font(row as Control, row_font_size)

func _show_loading() -> void:
	status_label.visible = true
	status_label.text = "Loading..."
	retry_button.visible = false
	_clear_rows()

func _on_top_updated(entries: Array[LeaderboardEntry]) -> void:
	_clear_rows()

	if not entries.is_empty():
		_populate(entries)
		return

	# An empty list means either "backend is down" or "nobody has played yet" -
	# different words, and only one of them offers a retry.
	var available: bool = LeaderboardManager.is_available
	retry_button.visible = not available
	status_label.visible = true
	status_label.text = "No scores yet" if available else "Leaderboard unavailable"
	_update_layout()

func _populate(entries: Array[LeaderboardEntry]) -> void:
	status_label.visible = false
	retry_button.visible = false

	var own_id: String = LeaderboardManager.get_player_id()

	for entry in entries:
		var is_own: bool = not own_id.is_empty() and entry.player_id == own_id
		rows_container.add_child(_build_row(entry, is_own))

	_update_own_rank_footer()
	_update_layout()

## The player's own standing is pinned below the scrolling list at all times, so
## it stays visible no matter how far they scroll - including when they are
## already somewhere in the list above.
func _update_own_rank_footer() -> void:
	var own_entry: LeaderboardEntry = LeaderboardManager.get_player_entry()

	own_rank_separator.visible = true
	own_rank_container.visible = true

	if own_entry != null and own_entry.rank > 0:
		own_rank_container.add_child(_build_row(own_entry, true))
		return

	# Ranked entry not known yet - say so rather than showing an empty strip.
	var placeholder: Label = Label.new()
	placeholder.text = "Noch keine Platzierung"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_color_override("font_color", Color(0.35, 0.29, 0.22, 1))
	own_rank_container.add_child(placeholder)

func _build_row(entry: LeaderboardEntry, is_own: bool) -> Control:
	var row: Control = ROW_SCENE.instantiate()
	(row.get_node("RankLabel") as Label).text = "%d." % entry.rank
	# Names are not unique - the document id is - so the colour tint alone is not
	# enough to pick yourself out of a list with a duplicate name in it.
	var display_name: String = entry.player_name
	if is_own:
		display_name += " (You)"
	(row.get_node("NameLabel") as Label).text = display_name
	(row.get_node("ScoreLabel") as Label).text = entry.format_score()
	(row.get_node("TimeLabel") as Label).text = entry.format_time()

	if is_own:
		row.modulate = OWN_ROW_COLOR

	return row

func _apply_row_font(row: Control, font_size: int) -> void:
	if row == null:
		return

	# The "no placement yet" strip is a bare Label, not a row.
	if row is Label:
		(row as Label).add_theme_font_size_override("font_size", font_size)
		return

	for label_name in ["RankLabel", "NameLabel", "ScoreLabel"]:
		var label := row.get_node_or_null(label_name) as Label
		if label:
			label.add_theme_font_size_override("font_size", font_size)

	var time_label := row.get_node_or_null("TimeLabel") as Label
	if time_label:
		time_label.add_theme_font_size_override("font_size", int(font_size * 0.85))

func _clear_rows() -> void:
	for row in rows_container.get_children():
		row.queue_free()
	for row in own_rank_container.get_children():
		row.queue_free()
	own_rank_separator.visible = false
	own_rank_container.visible = false

func _on_retry_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
	_show_loading()
	LeaderboardManager.refresh_top(true)

func _on_overlay_gui_input(event: InputEvent) -> void:
	if not PointerInput.is_pointer_press(event):
		return

	var press: Vector2 = PointerInput.press_position(event)
	if panel and not panel.get_global_rect().has_point(press):
		close()
