extends Node

## ReviewManager - occasionally asks the player to rate the game.
##
## Deliberately a plain in-game popup that deep-links to the store listing,
## rather than the native iOS rating overlay: no native plugin, and one code
## path for both stores.
##
## The popup is only ever opened by us at a natural pause, and the store link is
## only ever followed by an explicit tap on "Rate". That ordering matters -
## Apple's rule is that a review request must not be wired to a button the
## player pressed expecting one, and a deep link is the sanctioned way to send
## someone who has just said yes.

const CONFIG_PATH: String = "user://review.cfg"

const IOS_APP_ID: String = "6758386581"
const ANDROID_PACKAGE: String = "de.eliassteffen.wool"
## itms-apps:// opens the App Store app directly instead of bouncing via Safari.
const IOS_REVIEW_URL: String = "itms-apps://apps.apple.com/app/id%s?action=write-review"
## Play has no "write review" deep link; the listing is as close as it gets.
const ANDROID_REVIEW_URL: String = "market://details?id=%s"

## Gates. Kept conservative on purpose: a rating prompt that shows up twice is
## far worse than one that never shows.
const MIN_GAMES_BEFORE_ASK: int = 5
const DAYS_BETWEEN_ASKS: int = 90
const MAX_ASKS: int = 3

const PROMPT_SCENE: PackedScene = preload("res://scenes/ui/review_prompt.tscn")
## Above the game over screen's own CanvasLayer (layer 200).
const PROMPT_LAYER: int = 300

var _games_played: int = 0
var _asks_made: int = 0
var _last_ask_unix: int = 0
var _rated: bool = false
var _prompt: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()

# === PUBLIC METHODS ===

## True while the popup is on screen. game_over.gd checks this so a tap meant
## for the popup is not also read as "restart".
func is_prompt_open() -> bool:
	return _prompt != null and is_instance_valid(_prompt)

## Counts a completed run. Called from GameManager.game_over().
func notify_game_finished() -> void:
	_games_played += 1
	_save()

## Shows the popup if every gate passes. Safe to call at any time; returns
## whether it actually opened.
func maybe_prompt() -> bool:
	if not is_eligible():
		return false

	_prompt = PROMPT_SCENE.instantiate()
	_prompt.layer = PROMPT_LAYER
	_prompt.close_requested.connect(_on_prompt_closed)
	get_tree().root.add_child(_prompt)
	return true

func is_eligible() -> bool:
	# Someone who already went to the store has said their piece.
	if is_prompt_open() or _rated:
		return false
	# Desktop and web have nowhere to send them.
	if get_store_url().is_empty():
		return false
	# Ask on a high note, never after an ordinary run.
	if not GameManager.new_highscore_reached_this_run:
		return false
	if _games_played < MIN_GAMES_BEFORE_ASK:
		return false
	if _asks_made >= MAX_ASKS:
		return false

	if _last_ask_unix > 0:
		var elapsed: int = int(Time.get_unix_time_from_system()) - _last_ask_unix
		if elapsed < DAYS_BETWEEN_ASKS * 86400:
			return false

	return true

func get_store_url() -> String:
	match OS.get_name():
		"iOS":
			return IOS_REVIEW_URL % IOS_APP_ID
		"Android":
			return ANDROID_REVIEW_URL % ANDROID_PACKAGE
		_:
			return ""

## The player tapped "Rate". Opening the store is the one place a deep link
## belongs: they asked for it.
func accept() -> void:
	_rated = true
	_record_ask()

	var url: String = get_store_url()
	if not url.is_empty():
		OS.shell_open(url)

## The player tapped "Later" or dismissed the popup. Counts as an ask, so the
## cooldown and the lifetime cap both apply.
func decline() -> void:
	_record_ask()

# === PRIVATE METHODS ===

func _on_prompt_closed() -> void:
	if is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = null

func _record_ask() -> void:
	_asks_made += 1
	_last_ask_unix = int(Time.get_unix_time_from_system())
	_save()

func _load() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(CONFIG_PATH) != OK:
		return
	_games_played = int(config_file.get_value("review", "games_played", 0))
	_asks_made = int(config_file.get_value("review", "asks_made", 0))
	_last_ask_unix = int(config_file.get_value("review", "last_ask_unix", 0))
	_rated = bool(config_file.get_value("review", "rated", false))

func _save() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.set_value("review", "games_played", _games_played)
	config_file.set_value("review", "asks_made", _asks_made)
	config_file.set_value("review", "last_ask_unix", _last_ask_unix)
	config_file.set_value("review", "rated", _rated)
	config_file.save(CONFIG_PATH)
