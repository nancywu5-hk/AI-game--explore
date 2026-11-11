extends CanvasLayer

## Emitted when the user dismisses this window. UIManager listens and does the
## actual closing - see the "windows never close themselves" rule in ui_manager.gd.
signal close_requested

## Shown while the published row is being deleted. Switching off is the one
## action in this window that is not instant.
const PUBLISH_REMOVING: String = "Wird entfernt ..."

@onready var container: VBoxContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/ScrollContainer/VBoxContainer
@onready var content_margin: MarginContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin
@onready var scroll_container: ScrollContainer = $Control/OuterMargin/CenterContainer/Panel/ContentMargin/ScrollContainer
@onready var panel: Control = $Control/OuterMargin/CenterContainer/Panel

func _ready() -> void:
	var close_btn := get_node_or_null("Control/OuterMargin/CenterContainer/Panel/MenuBackground/CloseButton") as Button
	if close_btn:
		close_btn.pressed.connect(close)
	$Control.gui_input.connect(_on_overlay_gui_input)

	# Configure ScrollContainer for mobile scrolling
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_tree().root.size_changed.connect(_update_layout)
	call_deferred("_update_layout")

	# Find and setup sliders if they exist in the scene
	var master_slider = container.get_node_or_null("MasterVolume/VBoxContainer/HBoxContainer/HSlider")
	if master_slider: _setup_slider(master_slider, "Master")

	var music_slider = container.get_node_or_null("MusicVolume/VBoxContainer/HBoxContainer/HSlider")
	if music_slider: _setup_slider(music_slider, "Music")

	var sfx_slider = container.get_node_or_null("SFXVolume/VBoxContainer/HBoxContainer/HSlider")
	if sfx_slider: _setup_slider(sfx_slider, "SFX")

	_setup_publish_toggle()
	_setup_name_edit()

## The switch is a view onto LeaderboardManager's publish flag, not a setting of
## its own - so it follows the signal rather than only its own presses. Switching
## off in particular only settles once the row has actually been deleted, which
## happens well after the press.
func _setup_publish_toggle() -> void:
	var toggle := _publish_toggle()
	if not toggle:
		return

	toggle.toggled.connect(_on_publish_toggled)
	LeaderboardManager.publish_consent_changed.connect(_apply_publish_state)
	_apply_publish_state(LeaderboardManager.is_publishing())

func _publish_toggle() -> Button:
	return container.get_node_or_null("PublishScores/VBoxContainer/PublishToggle") as Button

func _publish_status() -> Label:
	return container.get_node_or_null("PublishScores/VBoxContainer/PublishStatus") as Label

func _name_edit() -> LineEdit:
	return container.get_node_or_null("PlayerName/VBoxContainer/NameEdit") as LineEdit

## Shows the state without acting on it - safe to call from the signal, which
## also fires for changes this window did not make.
func _apply_publish_state(consented: bool) -> void:
	var toggle := _publish_toggle()
	if toggle:
		# set_pressed_no_signal: assigning button_pressed would re-enter
		# _on_publish_toggled and hand the manager back its own change.
		toggle.set_pressed_no_signal(consented)
		toggle.text = "An" if consented else "Aus"
		# The theme points every button state at the same style box, so a
		# toggle would read identically on and off. Fading it back when off is
		# what makes the state visible at a glance rather than only readable.
		toggle.modulate = Color(1.0, 1.0, 1.0, 1.0 if consented else 0.6)

	# The name section stays visible either way: the name is the player's, asked
	# for at first launch and theirs to change whether or not anything is
	# published under it. Only re-read the field, in case switching on had to
	# mint a name.
	var name_edit := _name_edit()
	if name_edit:
		name_edit.text = LeaderboardManager.player_name

	_update_layout()

func _set_publish_status(message: String) -> void:
	var status := _publish_status()
	if not status:
		return
	status.text = message
	status.visible = not message.is_empty()
	_update_layout()

## On is instant and local; off has to erase a row that is already up there, so
## it waits on the network and can fail.
func _on_publish_toggled(pressed: bool) -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)

	if pressed:
		_set_publish_status("")
		# The stored best, not the last run: the switch publishes what the player
		# already has rather than making them earn it again.
		LeaderboardManager.enable_publishing(
			GameManager.highscore, GameManager.highscore_time_ms
		)
		return

	var toggle := _publish_toggle()
	if toggle:
		# A second press mid-delete would fire delete_entry at an identity that
		# is already being torn down.
		toggle.disabled = true
	_set_publish_status(PUBLISH_REMOVING)

	var result: LeaderboardResult = await LeaderboardManager.delete_entry()

	if not is_instance_valid(self) or not is_inside_tree():
		return
	if toggle:
		toggle.disabled = false

	if result.ok:
		# delete_entry already emitted publish_consent_changed(false), which came
		# back through _apply_publish_state and flipped the switch.
		_set_publish_status("")
		return

	# Offline or refused - the row is still on the board, so the switch must not
	# sit there claiming otherwise.
	_set_publish_status(result.get_display_message())
	_apply_publish_state(true)

func _setup_name_edit() -> void:
	var name_edit := _name_edit()
	if not name_edit:
		return

	name_edit.text = LeaderboardManager.player_name
	# Commit on Enter and on losing focus, so the value is never lost to a
	# tap-outside close.
	name_edit.text_submitted.connect(func(_new_text: String): _commit_name(name_edit))
	name_edit.focus_exited.connect(func(): _commit_name(name_edit))

## Commits immediately, offline included - nothing here needs the network.
func _commit_name(name_edit: LineEdit) -> void:
	var entered: String = LeaderboardEntry.sanitize_name(name_edit.text)

	# Empty or unchanged - nothing to do, just restore what is stored.
	if entered.is_empty() or entered == LeaderboardManager.player_name:
		name_edit.text = LeaderboardManager.player_name
		return

	LeaderboardManager.set_player_name(entered)

func _on_overlay_gui_input(event: InputEvent) -> void:
	if not PointerInput.is_pointer_press(event):
		return

	var press: Vector2 = PointerInput.press_position(event)
	if panel and not panel.get_global_rect().has_point(press):
		close()

func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var base_size: float = min(viewport_size.x, viewport_size.y)
	var inner_margin_x := clampf(viewport_size.x * 0.05, 20.0, 160.0)
	var inner_margin_top := clampf(viewport_size.y * 0.05, 20.0, 80.0)
	var inner_margin_bottom := clampf(viewport_size.y * 0.04, 20.0, 40.0)
	var section_font_size := int(clampf(base_size * 0.055, 30.0, 80.0))

	content_margin.add_theme_constant_override("margin_left", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_top", int(inner_margin_top))
	content_margin.add_theme_constant_override("margin_right", int(inner_margin_x))
	content_margin.add_theme_constant_override("margin_bottom", int(inner_margin_bottom))
	container.add_theme_constant_override("separation", int(clampf(viewport_size.y * 0.03, 16.0, 40.0)))

	# ScrollContainer doesn't reliably shrink-wrap to children; give it a sane height derived from content.
	var content_min: Vector2 = container.get_combined_minimum_size()
	var desired_h: float = content_min.y + inner_margin_top + inner_margin_bottom
	var max_h: float = max(220.0, viewport_size.y - 300.0)
	scroll_container.custom_minimum_size.y = clampf(desired_h, 260.0, max_h)

	var name_edit := _name_edit()
	if name_edit:
		name_edit.add_theme_font_size_override("font_size", int(clampf(base_size * 0.035, 22.0, 44.0)))
		# Width only - the styled box brings its own vertical padding.
		name_edit.custom_minimum_size = Vector2(clampf(viewport_size.x * 0.3, 240.0, 480.0), 0.0)

	# Sized like the leaderboard's buttons rather than left to wrap its label:
	# "An" and "Aus" are short enough that the button would otherwise change
	# width as it is pressed.
	var toggle := _publish_toggle()
	if toggle:
		toggle.add_theme_font_size_override("font_size", int(clampf(base_size * 0.04, 22.0, 48.0)))
		toggle.custom_minimum_size = Vector2(
			clampf(viewport_size.x * 0.24, 180.0, 320.0),
			clampf(base_size * 0.085, 56.0, 96.0)
		)

	# Smaller than a section heading: it is a transient status line under the
	# switch, not a fifth setting.
	var status := _publish_status()
	if status:
		status.add_theme_font_size_override(
			"font_size", int(clampf(base_size * 0.03, 18.0, 38.0))
		)

	for label_path in [
		"MasterVolume/VBoxContainer/Label",
		"MusicVolume/VBoxContainer/Label",
		"SFXVolume/VBoxContainer/Label",
		"PublishScores/VBoxContainer/Label",
		"PlayerName/VBoxContainer/Label",
	]:
		var label := container.get_node_or_null(label_path) as Label
		if label:
			label.add_theme_font_size_override("font_size", section_font_size)

func _setup_slider(slider: HSlider, bus_name: String) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01

	# Initialize value from current db
	if bus_idx != -1:
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))

	slider.value_changed.connect(func(val):
		var b_idx = AudioServer.get_bus_index(bus_name)
		if b_idx != -1:
			AudioServer.set_bus_volume_db(b_idx, linear_to_db(val))
	)

## Asks UIManager to close this window. Nothing here hides itself or touches
## get_tree().paused - the manager owns both.
func close() -> void:
	close_requested.emit()

## The name field commits on focus_exited; hiding a CanvasLayer does not drop
## focus, so a name typed and then dismissed by tap-outside would be lost.
func on_closed() -> void:
	var name_edit := _name_edit()
	if name_edit and name_edit.has_focus():
		name_edit.release_focus()

	# This window is cached and reused, so a failure message left on screen would
	# be waiting - stale - the next time it opens.
	_set_publish_status("")
