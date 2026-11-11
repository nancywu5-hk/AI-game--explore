extends Control

## Emitted when the user dismisses this window. UIManager listens, frees this
## instance along with the CanvasLayer it wrapped it in, and restores the window
## underneath - see the "windows never close themselves" rule in ui_manager.gd.
signal close_requested

var content: Control = null
var background: Control = null
var scroll_content: Control = null
var outer_margin: MarginContainer = null
var title_label: Label = null
var credits_text: RichTextLabel = null

var scroll_speed: float = 60.0
var _initial_y: float = 0.0
const DEBUG_CREDITS_LAYOUT := false
var _debug_last_layout_dump_ms: int = -10000
const FALLBACK_CREDITS_TEXT := "[center]\n[b]Art & Animation[/b]\nMischa\n\n[b]Developer[/b]\nElias\n\n[b]University[/b]\nFH Münster\nUniversity of Applied Sciences\nMünster School of Design (MSD) &\nElectrical Engineering and Computer Science (ETI)\n\n[i]Course[/i]\nGamedesign (Winter Semester 2025/26)\n\n[i]Supervised by[/i]\nProf. Dr. Kathrin Ungru-Baggemann\nProf. Dipl.-Des. Tina Glückselig\n\n[b]Fonts[/b]\nFrom Fontesk\n\n[font_size=60]Super Naive[/font_size]\nby All Super Font\n\n[font_size=60]Outline Style[/font_size]\nby Syafrizal a.k.a. Khurasan\n\n[b]Music & Sound[/b]\n\n[i]Music[/i]\n\"Kids Game Gaming Background Music\" by Maksym Malko from Pixabay\n\n[i]SFX[/i]\nFrom Freesound.org\n\n\"Rope Swooshing\" by Robo9418\n\"808BD_T1D7_X2wpo2.wav\" by bWpo\n\"Bamboo Swing, B5.wav\" by InspectorJ\n\"Message Notification 2\" by AnthonyRox\n\"vMax SourCream.wav\" by JFRecords\n\"bird_flapping_9.wav\" by Clusman\n\"Retro, Pew Shot.wav\" by LilMati\n\"fish_swim1\" by Rayo75\n\"CcubMetall01.wav\" by SuGu14\n\"soft button click 1\" by FOSSarts\n\"water-click.wav\" by CaptainYulef\n\"Whoosh -Plastic diving fin flat side - A-B 20cm - 1\" by Sadiquecat\n\n[b]Special Thanks[/b]\nGodot Engine Community\nOur Families\n[/center]"

func _get_content_height() -> float:
	if content == null:
		return 0.0
	return max(content.get_combined_minimum_size().y, content.size.y)

func _ready() -> void:
	_resolve_nodes()
	_ensure_content_nodes()
	_resolve_nodes()
	var close_btn := get_node_or_null("OuterMargin/CenterContainer/Background/MenuBackground/CloseButton") as Button
	if close_btn == null:
		# Fallback in case the instanced scene adds an extra root layer.
		close_btn = get_node_or_null("OuterMargin/CenterContainer/Background/MenuBackground/MenuBackground/CloseButton") as Button
	if close_btn == null:
		close_btn = get_node_or_null("OuterMargin/Background/MenuBackground/CloseButton") as Button
	if close_btn == null:
		close_btn = get_node_or_null("OuterMargin/Background/MenuBackground/MenuBackground/CloseButton") as Button
	if close_btn:
		close_btn.pressed.connect(_on_close_button_pressed)
	gui_input.connect(_on_overlay_gui_input)
	get_tree().root.size_changed.connect(_update_layout)
	call_deferred("_update_layout")

	# Start below the visible area
	if content:
		call_deferred("_reset_position")

	if DEBUG_CREDITS_LAYOUT:
		call_deferred("_debug_dump_layout", "_ready_deferred")

func _reset_position() -> void:
	if content == null or scroll_content == null:
		return

	# Wait until layout is valid (containers can report 0 size on first frame).
	var retries := 0
	while scroll_content.size.y <= 1.0 and retries < 5:
		await get_tree().process_frame
		retries += 1

	content.position.x = 0.0
	content.position.y = scroll_content.size.y + 40.0
	_initial_y = content.position.y
	if DEBUG_CREDITS_LAYOUT:
		_debug_dump_layout("_reset_position")

func _on_overlay_gui_input(event: InputEvent) -> void:
	if not PointerInput.is_pointer_press(event):
		return

	# Was get_viewport().get_mouse_position() for the mouse branch; event.position
	# is equivalent here (the overlay is a full-rect Control anchored at origin)
	# and is the only one that is also correct for a touch.
	var press: Vector2 = PointerInput.press_position(event)
	if DEBUG_CREDITS_LAYOUT:
		print("[credits_debug/input] press pos=", press, " panel_global_rect=", background.get_global_rect())
	if background and not background.get_global_rect().has_point(press):
		_on_close_button_pressed()

func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var base_size: float = min(viewport_size.x, viewport_size.y)
	if background == null or scroll_content == null or title_label == null or credits_text == null or outer_margin == null or content == null:
		return

	var outer_margin_px := 150.0
	var panel_size := background.size
	var inner_margin_x := clampf(panel_size.x * 0.05, 20.0, 180.0)
	var inner_margin_y := clampf(panel_size.y * 0.03, 16.0, 40.0)

	outer_margin.add_theme_constant_override("margin_left", int(outer_margin_px))
	outer_margin.add_theme_constant_override("margin_top", int(outer_margin_px))
	outer_margin.add_theme_constant_override("margin_right", int(outer_margin_px))
	outer_margin.add_theme_constant_override("margin_bottom", int(outer_margin_px))

	# Background is the authoritative viewport-bounded panel.
	# ScrollContent can be zero-sized in some container/layout combinations, so
	# compute content sizes directly from the panel.
	var available_w: float = max(panel_size.x - inner_margin_x * 2.0, 320.0)
	var available_h: float = max(panel_size.y - inner_margin_y * 2.0, 200.0)

	title_label.add_theme_font_size_override("font_size", int(clampf(base_size * 0.09, 42.0, 120.0)))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_text.add_theme_font_size_override("normal_font_size", int(clampf(base_size * 0.04, 22.0, 40.0)))
	credits_text.add_theme_font_size_override("bold_font_size", int(clampf(base_size * 0.06, 30.0, 80.0)))
	credits_text.add_theme_font_size_override("italics_font_size", int(clampf(base_size * 0.05, 26.0, 60.0)))
	credits_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	credits_text.custom_minimum_size = Vector2(available_w, max(available_h * 1.5, 600.0))
	content.custom_minimum_size = Vector2(available_w, max(available_h * 1.8, 760.0))
	if DEBUG_CREDITS_LAYOUT:
		_debug_dump_layout("_update_layout")
	call_deferred("_reset_position")

func _process(delta: float) -> void:
	if content:
		var current_speed = scroll_speed

		# Check for hold input (Left Mouse or Touch)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			current_speed *= 4.0

		content.position.y -= current_speed * delta

		# Reset if it goes too far up (off screen top)
		if content.position.y + _get_content_height() < 0.0:
			if DEBUG_CREDITS_LAYOUT:
				_debug_dump_layout("_process_before_loop_reset")
			call_deferred("_reset_position")

		if DEBUG_CREDITS_LAYOUT:
			var now_ms := Time.get_ticks_msec()
			if now_ms - _debug_last_layout_dump_ms >= 1000:
				_debug_dump_layout("_process_tick")
				_debug_last_layout_dump_ms = now_ms

func _on_close_button_pressed() -> void:
	close_requested.emit()

func _debug_dump_layout(tag: String) -> void:
	if not DEBUG_CREDITS_LAYOUT:
		return

	var viewport := get_viewport()
	if viewport == null:
		print("[credits_debug/", tag, "] viewport=null")
		return
	if outer_margin == null or background == null or scroll_content == null or content == null or title_label == null or credits_text == null:
		print("[credits_debug/", tag, "] nodes_not_ready outer=", outer_margin, " background=", background, " scroll=", scroll_content, " content=", content, " title=", title_label, " credits_text=", credits_text)
		return

	var camera := viewport.get_camera_2d()
	var camera_info := "none"
	if camera:
		camera_info = "pos=%s zoom=%s global_pos=%s enabled=%s current=%s" % [
			str(camera.position),
			str(camera.zoom),
			str(camera.global_position),
			str(camera.enabled),
			str(camera.is_current())
		]

	var left_margin := outer_margin.get_theme_constant("margin_left")
	var top_margin := outer_margin.get_theme_constant("margin_top")
	var right_margin := outer_margin.get_theme_constant("margin_right")
	var bottom_margin := outer_margin.get_theme_constant("margin_bottom")

	print("[credits_debug/", tag, "]")
	print("  window_size=", DisplayServer.window_get_size(), " viewport_rect=", viewport.get_visible_rect(), " root_size=", get_tree().root.size)
	print("  camera2d=", camera_info)
	print("  outer_margin_size=", outer_margin.size, " margins(l,t,r,b)=", Vector4(left_margin, top_margin, right_margin, bottom_margin))
	print("  background_size=", background.size, " background_global_rect=", background.get_global_rect(), " background_offsets=", Vector4(background.offset_left, background.offset_top, background.offset_right, background.offset_bottom))
	print("  scroll_content_size=", scroll_content.size, " scroll_content_global_rect=", scroll_content.get_global_rect(), " scroll_offsets=", Vector4(scroll_content.offset_left, scroll_content.offset_top, scroll_content.offset_right, scroll_content.offset_bottom))
	print("  content_pos=", content.position, " content_size=", content.size, " content_min=", content.get_combined_minimum_size(), " initial_y=", _initial_y)
	print("  title_size=", title_label.size, " title_global_rect=", title_label.get_global_rect(), " title_font_size=", title_label.get_theme_font_size("font_size"))
	print("  credits_text_size=", credits_text.size, " credits_text_global_rect=", credits_text.get_global_rect(), " credits_text_min=", credits_text.custom_minimum_size, " h_align=", credits_text.horizontal_alignment, " fit_content=", credits_text.fit_content, " autowrap=", credits_text.autowrap_mode)

func _resolve_nodes() -> void:
	outer_margin = get_node_or_null("OuterMargin") as MarginContainer
	background = get_node_or_null("OuterMargin/CenterContainer/Background") as Control
	if background == null:
		background = get_node_or_null("OuterMargin/Background") as Control
	scroll_content = get_node_or_null("OuterMargin/CenterContainer/Background/ScrollContent") as Control
	if scroll_content == null:
		scroll_content = get_node_or_null("OuterMargin/Background/ScrollContent") as Control
	content = get_node_or_null("OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer") as Control
	if content == null:
		content = get_node_or_null("OuterMargin/Background/ScrollContent/VBoxContainer") as Control
	title_label = get_node_or_null("OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer/Title") as Label
	if title_label == null:
		title_label = get_node_or_null("OuterMargin/Background/ScrollContent/VBoxContainer/Title") as Label
	credits_text = get_node_or_null("OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer/CreditsText") as RichTextLabel
	if credits_text == null:
		credits_text = get_node_or_null("OuterMargin/Background/ScrollContent/VBoxContainer/CreditsText") as RichTextLabel

	# Fallback paths if the scene root is wrapped unexpectedly.
	if outer_margin == null:
		outer_margin = get_node_or_null("CreditsScreen/OuterMargin") as MarginContainer
	if background == null:
		background = get_node_or_null("CreditsScreen/OuterMargin/CenterContainer/Background") as Control
	if scroll_content == null:
		scroll_content = get_node_or_null("CreditsScreen/OuterMargin/CenterContainer/Background/ScrollContent") as Control
	if content == null:
		content = get_node_or_null("CreditsScreen/OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer") as Control
	if title_label == null:
		title_label = get_node_or_null("CreditsScreen/OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer/Title") as Label
	if credits_text == null:
		credits_text = get_node_or_null("CreditsScreen/OuterMargin/CenterContainer/Background/ScrollContent/VBoxContainer/CreditsText") as RichTextLabel

	# Robust recursive fallback: find nodes under Background by name/type, regardless of exact nesting.
	if background != null:
		if scroll_content == null:
			scroll_content = _find_descendant_control(background, "ScrollContent")
		if content == null:
			content = _find_descendant_control(background, "VBoxContainer")
		if title_label == null:
			title_label = _find_descendant_label(background, "Title")
		if credits_text == null:
			credits_text = _find_descendant_rich_text(background, "CreditsText")

	# Last-resort fallback to keep layout logic alive even with partial scene differences.
	if scroll_content == null:
		scroll_content = background
	if content == null:
		content = scroll_content

	if DEBUG_CREDITS_LAYOUT:
		print("[credits_debug/resolve] outer=", outer_margin, " background=", background, " scroll=", scroll_content, " content=", content, " title=", title_label, " credits_text=", credits_text)
		if background != null and (scroll_content == null or title_label == null or credits_text == null):
			print("[credits_debug/resolve] background_children=", _debug_children_names(background))

func _find_descendant_control(root: Node, wanted_name: String) -> Control:
	for child in root.get_children():
		if child is Control and child.name == wanted_name:
			return child as Control
		var nested := _find_descendant_control(child, wanted_name)
		if nested != null:
			return nested
	return null

func _find_descendant_label(root: Node, wanted_name: String) -> Label:
	for child in root.get_children():
		if child is Label and child.name == wanted_name:
			return child as Label
		var nested := _find_descendant_label(child, wanted_name)
		if nested != null:
			return nested
	return null

func _find_descendant_rich_text(root: Node, wanted_name: String) -> RichTextLabel:
	for child in root.get_children():
		if child is RichTextLabel and child.name == wanted_name:
			return child as RichTextLabel
		var nested := _find_descendant_rich_text(child, wanted_name)
		if nested != null:
			return nested
	return null

func _ensure_content_nodes() -> void:
	if background == null:
		return
	if scroll_content != null and content != null and title_label != null and credits_text != null:
		return

	# Build missing credits content tree at runtime as a safety fallback.
	var generated_scroll := Control.new()
	generated_scroll.name = "ScrollContent"
	generated_scroll.clip_contents = true
	generated_scroll.anchors_preset = Control.PRESET_FULL_RECT
	generated_scroll.anchor_right = 1.0
	generated_scroll.anchor_bottom = 1.0
	generated_scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	generated_scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
	generated_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var generated_vbox := VBoxContainer.new()
	generated_vbox.name = "VBoxContainer"
	generated_vbox.anchors_preset = Control.PRESET_TOP_WIDE
	generated_vbox.anchor_right = 1.0
	generated_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	generated_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generated_vbox.add_theme_constant_override("separation", 60)
	generated_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var generated_title := Label.new()
	generated_title.name = "Title"
	generated_title.text = "CREDITS"
	generated_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	generated_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var generated_text := RichTextLabel.new()
	generated_text.name = "CreditsText"
	generated_text.bbcode_enabled = true
	generated_text.text = FALLBACK_CREDITS_TEXT
	generated_text.fit_content = false
	generated_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	generated_text.scroll_active = false
	generated_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generated_text.custom_minimum_size = Vector2(320, 0)
	generated_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	generated_vbox.add_child(generated_title)
	generated_vbox.add_child(generated_text)
	generated_scroll.add_child(generated_vbox)
	background.add_child(generated_scroll)

	if DEBUG_CREDITS_LAYOUT:
		print("[credits_debug/fallback] generated missing credits content nodes under Background")

func _debug_children_names(root: Node) -> String:
	var names: Array[String] = []
	for child in root.get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	return "[" + ", ".join(names) + "]"
