class_name Wool
extends BasePlayer

# === ONREADY VARIABLES ===
# Pickaxe
@onready var pickaxe: Sprite2D = $Pickaxe
@onready var pickaxe_pivot: Marker2D = $PickaxePivot

# Physics Shapes
@onready var physics_shape_default: CollisionShape2D = $PhysicsShape

# Hitbox Shapes
@onready var hitbox_shape_default: CollisionShape2D = $HitboxArea/HitboxShape

# Pickaxe State
var _initial_pickaxe_position: Vector2
var _initial_pickaxe_rotation: float
var _initial_pickaxe_scale: Vector2
var _initial_pickaxe_centered: bool = true
var _initial_pickaxe_offset: Vector2 = Vector2.ZERO
var _is_jumping_active: bool = false # Tracks if a jump was voluntarily initiated
var _game_started: bool = false # Tracks if the game has started
var _current_shape_animation: String = ""
var _idle_timer: float = 0.0
var _last_played_anim: String = ""
var _extra_gravity: float = 0.0 # Extra gravity when trying to grapple without nails nearby
var _ignore_hold_gravity: bool = false # Ignore hold input for fast-fall until first release

# Shadows
@onready var shadow_pickaxe: Sprite2D = $ShadowPickaxe
@onready var shadow_skin: AnimatedSprite2D = $ShadowSkin
const SHADOW_OFFSET: Vector2 = Vector2(100, 100)

# Pickaxe Grapple Configuration
# Assign a Marker2D node here (e.g. child of Pickaxe) to visually define the grapple connection point.
@export var grapple_marker: Marker2D

func _ready() -> void:
	super._ready()

	# Fix Jump Interaction
	if skin and skin.animated_sprite and skin.animated_sprite.sprite_frames:
		if skin.animated_sprite.sprite_frames.has_animation("jump"):
			skin.animated_sprite.sprite_frames.set_animation_loop("jump", false)

	if pickaxe:
		_initial_pickaxe_position = pickaxe.position
		_initial_pickaxe_rotation = pickaxe.rotation
		_initial_pickaxe_scale = pickaxe.scale
		_initial_pickaxe_centered = pickaxe.centered
		_initial_pickaxe_offset = pickaxe.offset

func _process(delta: float) -> void:
	super._process(delta)

	if current_anim_state == PlayerState.IDLE:
		_idle_timer += delta
	else:
		_idle_timer = 0.0

	_update_pickaxe_visual()
	_update_shadows()
	_update_nail_highlight()

# === OVERRIDDEN METHODS FOR BASE PLAYER ===

func get_grapple_offset() -> Vector2:
	# Use the visual marker if assigned
	if grapple_marker:
		return grapple_marker.global_position - global_position

	# Fallback: Calculate from pickaxe center if it exists
	if pickaxe:
		# Default to pickaxe center/origin
		return pickaxe.global_position - global_position

	return Vector2.ZERO

func _jump() -> void:
	super._jump()
	if not self is ShadowWool:
		AudioManager.play_sound(AudioManager.WOOL.SCHWINGEN)
	_is_jumping_active = true

func _calculate_player_state() -> PlayerState:
	if grappling_feature and grappling_feature.is_active():
		return PlayerState.GRAPPLE

	# Immediate Jump Response on Input or Flag
	var jump_just_pressed = Input.is_action_just_pressed("jump")

	if _is_jumping_active or jump_just_pressed:
		return PlayerState.JUMP

	# Floating/Falling State
	if not is_on_floor():
		return PlayerState.JUMP

	# Check for horizontal movement (Walking)
	if not is_zero_approx(velocity.x):
		return PlayerState.WALK

	return PlayerState.IDLE

func _should_force_animation_update() -> bool:
	# FORCE UPDATE FOR IDLE DELAY
	if current_anim_state == PlayerState.IDLE:
		# If timer just crossed threshold, force update to start playing animation
		if _idle_timer >= CharacterConstants.IDLE_ANIMATION_DELAY:
			if skin and skin.animated_sprite and not skin.animated_sprite.is_playing():
				return true

	# SAFETY CHECK: Ensure Walk/Jump animations don't get stuck
	# If we are walking or jumping, the animation should strictly be playing.
	# This catches cases where an animation finished (non-looping) or was paused errantly.
	if current_anim_state != PlayerState.IDLE:
		if skin and skin.animated_sprite and not skin.animated_sprite.is_playing():
			return true

	return false

func _play_animation_for_state(state: PlayerState) -> void:
	var target_anim = "idle"

	match state:
		PlayerState.IDLE: target_anim = "idle"
		PlayerState.WALK: target_anim = "walk"
		PlayerState.GRAPPLE:
			# DYNAMIC: Detect swing direction for visual feedback
			var is_ccw_swing = true
			var current_nail = grappling_feature.get_target_nail()
			if current_nail:
				var rope_vector = current_nail.global_position - global_position
				# Cross product in 2D to determine rotation direction
				# (rope.x * vel.y - rope.y * vel.x)
				var cross = rope_vector.x * velocity.y - rope_vector.y * velocity.x
				is_ccw_swing = cross > 0

			target_anim = "grapple_ccw" if is_ccw_swing else "grapple_cw"

		PlayerState.JUMP: target_anim = "jump"

	if skin:
		# PLAY ANIMATION
		# Only play if the animation actually changed.
		if target_anim != _last_played_anim:
			# SPECIAL CASE: Skip windup for Jump (Frame 5 Start)
			if target_anim == "jump":
				skin.play_animation(target_anim)
				if skin.animated_sprite:
					skin.animated_sprite.frame = 5
			else:
				# Standard Play
				skin.play_animation(target_anim)

			_last_played_anim = target_anim
		elif target_anim == "walk" or target_anim == "idle":
			# Ensure looping animations are playing (in case they stopped due to frame errors)
			if skin.animated_sprite and not skin.animated_sprite.is_playing():
				skin.animated_sprite.play()

var _current_visual_rotation: float = 0.0
var _last_valid_floor_normal: Vector2 = Vector2.UP

func _update_rotation(delta: float) -> void:
	# OVERRIDE: Do not call super._update_rotation(delta)
	# We handle rotation manually on the visuals (Skin/Hitbox) ONLY.
	# Rotating the CharacterBody2D (self) causes floor detachment on slopes.

	var is_grappling = grappling_feature and grappling_feature.is_active()
	var target_rotation = 0.0

	# --- FORCE RIGHT FACING ---
	_update_facing_direction(false) # Always face right
	# ---------------------------

	if is_grappling:
		var current_nail = grappling_feature.get_target_nail()
		if current_nail:
			var rope_vector = current_nail.global_position - global_position

			# Decay Impulse (Slower decay for better visibility)
			_grapple_kick = move_toward(_grapple_kick, 0.0, delta * 3.0)

			# DYNAMIC Lean based on swing direction
			var cross = rope_vector.x * velocity.y - rope_vector.y * velocity.x
			var is_ccw = cross > 0
			var target_lean = deg_to_rad(-40.0) if is_ccw else deg_to_rad(40.0)

			# Align head with rope (rope angle + 90 deg) + Kick + Lean
			target_rotation = rope_vector.angle() + PI / 2.0 + _grapple_kick + target_lean
	elif is_on_floor():
		# Align with floor slope
		var floor_normal = get_floor_normal()
		target_rotation = floor_normal.angle() + PI / 2.0
		_last_valid_floor_normal = floor_normal
	else:
		# In Air logic
		if velocity.y > 100.0:
			# FLIGHT / FALLING: Rotate slightly CW
			target_rotation = deg_to_rad(15.0)
		elif velocity.y < -50.0:
			# JUMPING: Rotate to 0 (Upright)
			target_rotation = 0.0
		else:
			# APEX / FLICKER FIX:
			# Use last known floor normal to maintain rotation during momentary flickers (e.g. running down slopes)
			target_rotation = _last_valid_floor_normal.angle() + PI / 2.0

	# Apply rotation with smoothing to the VISUAL ROTATION variable
	var rotate_speed = 15.0 if is_on_floor() else 5.0
	_current_visual_rotation = lerp_angle(_current_visual_rotation, target_rotation, rotate_speed * delta)

	# Apply to Skin
	if skin:
		skin.rotation = _current_visual_rotation

		# Fix floating on slopes (Visual Offset)
		# Improved: Rely on visual rotation (which handles flickers) to set offset
		# This prevents the 'snap to 0' when is_on_floor() flickers false momentarily
		var slope_offset = abs(sin(_current_visual_rotation)) * 10.0
		skin.position.y = lerp(skin.position.y, slope_offset, 20.0 * delta)

	# Apply to Hitbox Area (if exists)
	if has_node("HitboxArea"):
		$HitboxArea.rotation = _current_visual_rotation
		if skin:
			# Also sync position offset
			$HitboxArea.position.y = skin.position.y



func _process_physics(delta: float) -> void:
	super._process_physics(delta)

	# Apply extra gravity when trying to grapple without nails nearby
	if _extra_gravity > 0.0:
		velocity.y += _extra_gravity * delta

	# Only reset jumping logic if we are actually on floor AND falling/standing (not moving up/jumping)
	# This prevents resetting the jump flag immediately in the frame we jump (where is_on_floor is still true)
	if is_on_floor() and velocity.y >= 0:
		_is_jumping_active = false

	# Increase floor snap length to handle steep slopes better at high speeds
	# BUT: Only apply high snap if we didn't just jump. Otherwise we snap back to ground instantly.
	if not _just_jumped:
		floor_snap_length = 64.0

func _update_pickaxe_visual() -> void:
	if not pickaxe:
		return

	var is_grappling: bool = grappling_feature and grappling_feature.is_active()
	var current_nail: BaseNail = null

	if is_grappling and grappling_feature:
		var target = grappling_feature.get_target_nail()
		if is_instance_valid(target) and target is BaseNail:
			current_nail = target as BaseNail

	if is_grappling and current_nail:
		# Show pickaxe as rope stretching from player to nail
		pickaxe.visible = true

		# Use pivot if available, otherwise player position
		var c_player: Vector2 = pickaxe_pivot.global_position if pickaxe_pivot else global_position
		var c_nail: Vector2 = current_nail.global_position

		# Vector and distance
		var rope_vector: Vector2 = c_nail - c_player
		var rope_distance: float = rope_vector.length()
		var rope_angle: float = rope_vector.angle()

		# Original Sprite Dimensions
		var texture_size: Vector2 = pickaxe.texture.get_size()

		# --- VISUAL SCALING LOGIC ---
		# User Request: Stretch along X axis (Width) to reach the nail

		# 1. Position: Pivot (Spielerhand)
		pickaxe.global_position = c_player

		# 2. Richtung: Vektor von Pivot zu Nail (bereits oben definiert)
		# rope_vector, rope_distance, rope_angle sind schon vorhanden!

		# 3. Rotation: Sprite-Y (-Y Axis) should point to Nail
		# Standard Sprite points UP (-Y). So we align -Y with rope_vector.
		# rope_angle is angle of X axis. To make -Y align with X, we rotate +90 deg.
		pickaxe.global_rotation = rope_angle + PI / 2.0

		# 4. Offset: Ursprung an unteren Rand (EdgeBottom)
		var height: float = texture_size.y
		if height < 1.0: height = 1.0
		# We want the Bottom of the sprite (max Y) to be at (0,0).
		pickaxe.offset = Vector2(0, -height * 0.5)
		pickaxe.centered = true

		# 5. Skalierung: Y so, dass EdgeTop = Nail
		# IMPORTANT: We must calculate distance in PARENT LOCAL SPACE to account for Parent Scaling (e.g. 0.1)
		# to_local converts Global -> Parent Local (since script is on Parent)
		var local_start = to_local(c_player)
		var local_end = to_local(c_nail)
		var dist_in_parent = local_start.distance_to(local_end)

		# Scale Y to match distance in local space
		pickaxe.scale = Vector2(1.0, dist_in_parent / height)



		# Ensure visibility
		pickaxe.visible = true
		pickaxe.z_index = 1 # Between Nail Back (0/-1) and Nail Front (2/1)
	else:
		# Restore initial state
		if pickaxe:
			pickaxe.visible = true
			pickaxe.centered = _initial_pickaxe_centered
			pickaxe.offset = _initial_pickaxe_offset
			pickaxe.scale = _initial_pickaxe_scale
			pickaxe.z_index = 0

		# Facings
		var facing_left = false
		if skin:
			facing_left = skin.scale.x < 0

		# Define base position/rotation
		var base_pos = _initial_pickaxe_position
		var base_rot = _initial_pickaxe_rotation
		var base_scale = _initial_pickaxe_scale

		# Note: We do NOT force position to pivot here anymore,
		# as pivot is only used during attack animation.

		if facing_left:
			# Mirror X position
			pickaxe.position = Vector2(-base_pos.x, base_pos.y)
			# Mirror Scale X
			pickaxe.scale = Vector2(-base_scale.x, base_scale.y)
			# Invert rotation for symmetry
			pickaxe.rotation = -base_rot
		else:
			pickaxe.position = base_pos
			pickaxe.scale = base_scale
			pickaxe.rotation = base_rot

		# --- DYNAMIC MOVEMENT (Backpack Style) ---
		var time = Time.get_ticks_msec() / 1000.0
		var dynamic_y = 0.0
		var dynamic_r = 0.0

		# Define visual grounded state (Use coyote timer to bridge physics flickers on slopes)
		var is_visually_grounded = is_on_floor() or _coyote_timer > 0.0

		# 1. Walking Bob (On Floor)
		if is_visually_grounded and abs(velocity.x) > 10.0:
			# Bobbing up and down
			dynamic_y = sin(time * 15.0) * 3.0
			# Slight rotation sway
			dynamic_r = cos(time * 15.0) * 0.1

		# 2. Air Physics (Jumping/Falling)
		if not is_visually_grounded:
			# Tilt based on vertical velocity (lag behind movement)
			# dragging behind -> rotates opposite to velocity direction visually
			dynamic_r = clamp(velocity.y * 0.001, -0.3, 0.3)

		# Apply dynamics
		pickaxe.position.y += dynamic_y

		# Apply rotation correctly based on facing
		if skin and skin.scale.x < 0:
			pickaxe.rotation -= dynamic_r
		else:
			pickaxe.rotation += dynamic_r

		# 3. Apply Visual Rotation (Slope) to Pickaxe
		# Pickaxe is child of Wool (unrotated), so we must manually add the visual rotation
		# to match the skin.
		# ONLY applied when visually grounded (slopes). In air, we want Wool to rotate but NOT the pickaxe.
		if is_visually_grounded:
			pickaxe.rotation += _current_visual_rotation

		# Sync Position offset with skin (floating fix)
		if skin:
			pickaxe.position.y += skin.position.y
		# ----------------------------------------

## Override to handle Wool-specific shape mirroring
# Use BasePlayer logic primarily, but force pickaxe update
func _update_facing_direction(is_facing_left: bool) -> void:
	# Call base to update skin and hitbox scale
	super._update_facing_direction(is_facing_left)

	# Force pickaxe visual update immediately
	# But wrap in check to ensure pickaxe is valid, as this might be called during setup
	if pickaxe:
		_update_pickaxe_visual()



# === MOBILE / ONE-BUTTON GAMEPLAY LOGIC ===
# Overrides BasePlayer input handling for the requested mobile loop.

var _input_jump_pressed_latched: bool = false
var _input_jump_held: bool = false
var _active_touch_indices: Dictionary = {}

func _unhandled_input(event: InputEvent) -> void:
	# Handle Multi-Touch specific logic
	if event is InputEventScreenTouch:
		if event.pressed:
			_active_touch_indices[event.index] = true
			_input_jump_pressed_latched = true # Also trigger jump
		else:
			_active_touch_indices.erase(event.index)

			# If NO touches are left, we consider the "jump/grapple" released
			if _active_touch_indices.is_empty():
				_ignore_hold_gravity = false

		# We generally DON'T consume the event here (set_input_as_handled)
		# because we want other systems (like UI) to potentially see it if they are on top.
		# However, _unhandled_input is only called if UI didn't consume it.
		return

	# Fallback for Mouse/Keyboard (or if touch emulation is on but we want redundancy)
	if event.is_action_pressed("jump"):
		_input_jump_pressed_latched = true
		_input_jump_held = true
	elif event.is_action_released("jump"):
		_input_jump_held = false
		_ignore_hold_gravity = false

func _handle_input() -> void:
	# 1. Unified Input Action: "jump" (Space / Touch / Click)
	# We treat any main action as the single input.
	# Using virtual methods to allow ShadowWool to override
	var input_just_pressed: bool = _get_jump_just_pressed()

	# Pressed is true if standard action is held OR if we have active touches
	var input_pressed: bool = _get_jump_held() or not _active_touch_indices.is_empty()

	# Fallback for "Space" key if UI didn't consume it (optional redundancy)
	# but strictly relying on unhandled_input is cleaner for UI blocking.

	if not _game_started:
		_direction = 0.0
		if input_just_pressed:
			# Check if start icons still exist - if yes, ignore this input (it's for the animation)
			var level = get_parent()
			var start_icons = level.get_node_or_null("Starticons") if level else null

			if start_icons and is_instance_valid(start_icons):
				# Start icons still exist - this input is for the animation, not for jumping
				return

			# Game start logic
			_game_started = true

			_ignore_hold_gravity = true
			_jump()
			_direction = 1.0
			velocity.x = move_speed # Instant burst to right
		return

	# 2. Ground Logic: Auto-run & Tap to Jump
	if is_on_floor():
		_direction = 1.0 # Always run right on ground
		if input_just_pressed:
			_jump()

	# 3. Air Logic: Hold to Grapple / Release to Fly
	else:
		# Preserve momentum direction in air (handle back-swings)
		if abs(velocity.x) > 10.0:
			_direction = sign(velocity.x)
		else:
			_direction = 1.0

		var is_grappling: bool = grappling_feature and grappling_feature.is_active()

		# Allow grapple activation only if we are NOT in the initial jump frame
		# (Though typically distinct taps are handled, a hold is needed)
		if input_pressed:
			# HOLDING
			if not is_grappling:
				var best_nail: Interaction = _find_best_grapple_target()
				if best_nail:
					# Reset held latch on grapple start to prevent immediate re-release issues if sync is off?
					# No, keep it true as long as held.
					grappling_feature.set_target(best_nail.get_grapple_point(), best_nail)
					AudioManager.play_sound(AudioManager.WOOL.HOOK)
				else:
					# No nails nearby, but trying to grapple - increase gravity
					# Only apply if we are not ignoring the hold (initial start hold)
					if not _ignore_hold_gravity:
						_extra_gravity = gravity * 2.0
					else:
						_extra_gravity = 0.0
			else:
				_extra_gravity = 0.0
		else:
			# RELEASED
			if is_grappling:
				grappling_feature.release()
				AudioManager.play_sound(AudioManager.WOOL.SCHWINGEN)

			_extra_gravity = 0.0

	# 4. Vertical Input (Swim/Climb) - currently zeroed for one-button simplicity
	_vertical_direction = 0.0

# === VIRTUAL INPUT METHODS ===
func _get_jump_just_pressed() -> bool:
	var pressed = _input_jump_pressed_latched
	_input_jump_pressed_latched = false
	# Redundancy check only if we really want strict hybrid input
	return pressed

func _get_jump_held() -> bool:
	return _input_jump_held



func _find_best_grapple_target() -> Interaction:
	var best_target: Interaction = null
	var best_score: float = -INF

	# Weights for selection criteria
	var w_forward: float = 1.0
	var w_up: float = 1.5 # Slight preference for height to keep momentum

	# Scan all nearby interactions
	for interaction in nearby_interactions:
		if interaction is BaseNail and not interaction.is_being_used():
			var nail_pos = interaction.global_position
			var player_pos = global_position

			# Relative Position
			var dx = nail_pos.x - player_pos.x
			var dy = player_pos.y - nail_pos.y # Inverted because godot Y is down (-Y is Up)

			# Score Calculation
			# We want to maximize Forward (dx) and Up (dy)
			var score = (dx * w_forward) + (dy * w_up)

			# Filter: Optional strict check?
			# User said PREFER, so let the score handle it.
			# A nail behind (-dx) will have a negative score and likely be beaten by any forward nail.

			if score > best_score:
				best_score = score
				best_target = interaction

	return best_target

func _handle_grapple_swing_pump(delta: float) -> void:
	# "Character should automatically swing left and right"
	# We override the pump logic to be automatic based on momentum orientation.

	# If we have speed, pump in that direction to maintain momentum
	if abs(velocity.x) > 10.0:
		_direction = sign(velocity.x)
	else:
		# If stalled or starting, nudge forward (Right) or based on position relative to nail?
		# Nudge Right by default for progress
		_direction = 1.0

	# Store the auto-direction so super() can use it
	super._handle_grapple_swing_pump(delta)

func _update_shadows() -> void:
	# Synchronize Skin Shadow
	if skin and shadow_skin:
		shadow_skin.visible = skin.visible
		# Skin is a Node2D container, effectively the pivot.
		shadow_skin.position = skin.position + SHADOW_OFFSET
		shadow_skin.rotation = skin.rotation
		# ShadowSkin sits next to Skin, not inside it, so it has to pick up the
		# inner sprite's scale too. That scale is not 1:1 - it compensates for the
		# downscaled atlas - and reading only skin.scale renders the shadow at a
		# fraction of the body.
		shadow_skin.scale = skin.scale
		if skin.animated_sprite:
			shadow_skin.scale *= skin.animated_sprite.scale

		# Sync Animation
		if skin.animated_sprite:
			var anim_sprite = skin.animated_sprite
			if anim_sprite.sprite_frames:
				shadow_skin.sprite_frames = anim_sprite.sprite_frames

			shadow_skin.animation = anim_sprite.animation
			shadow_skin.frame = anim_sprite.frame
			shadow_skin.flip_h = anim_sprite.flip_h
			shadow_skin.flip_v = anim_sprite.flip_v


	# Synchronize Pickaxe Shadow
	if pickaxe and shadow_pickaxe:
		shadow_pickaxe.visible = pickaxe.visible
		shadow_pickaxe.position = pickaxe.position + SHADOW_OFFSET
		# Rotation/Scale/Offset/Centered from pickaxe
		shadow_pickaxe.rotation = pickaxe.rotation
		shadow_pickaxe.scale = pickaxe.scale
		shadow_pickaxe.offset = pickaxe.offset
		shadow_pickaxe.centered = pickaxe.centered

		if pickaxe.texture:
			shadow_pickaxe.texture = pickaxe.texture

		# Keep Z-Index fixed at -1
		shadow_pickaxe.z_index = -1

# === NAIL HIGHLIGHTING ===
var _current_highlighted_nail: BaseNail = null

func _update_nail_highlight() -> void:
	# If we are already grappling, we don't need to highlight new targets
	# (OR: maybe we DO if we want to show where we'd switch to? For now, disable in grapple state for clarity)
	var is_grappling = grappling_feature and grappling_feature.is_active()

	var best_nail: BaseNail = null
	if not is_grappling:
		# Use the same logic as the actual grapple check
		var target = _find_best_grapple_target()
		if target and target is BaseNail:
			best_nail = target as BaseNail

	# Update State
	if _current_highlighted_nail != best_nail:

		# Unhighlight old
		if is_instance_valid(_current_highlighted_nail):
			_current_highlighted_nail.set_highlight(false)

		_current_highlighted_nail = best_nail

		# Highlight new
		if is_instance_valid(_current_highlighted_nail):
			_current_highlighted_nail.set_highlight(true)
