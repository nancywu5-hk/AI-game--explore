extends Node

# --- Constants for Sound Access ---
const WOOL = {
	HOOK = "wool_hook",
	DIE = "wool_die",
	SCHWINGEN = "wool_swing",
	FALLING = "wool_falling"
}

const ENEMIES = {
	BIRD = "enemy_bird",
	SPUCKI = "enemy_spucki",
	FISH_START = "enemy_fish_start",
	FISH_END = "enemy_fish_end"
}

const GAME = {
	ANFANG = "game_start",
	HIGHSCORE = "game_highscore",
	WARN = "game_warn",
	CLICK = "ui_click"
}

# Values map to file paths
var _sound_files = {
	WOOL.HOOK: "res://assets/sound/wool/hook.wav",
	WOOL.DIE: "res://assets/sound/wool/die.wav",
	WOOL.SCHWINGEN: "res://assets/sound/wool/swing.wav",

	ENEMIES.BIRD: "res://assets/sound/enemies/bird.wav",
	ENEMIES.SPUCKI: "res://assets/sound/enemies/spucki.wav",
	ENEMIES.FISH_START: "res://assets/sound/enemies/fish-start.wav",
	ENEMIES.FISH_END: "res://assets/sound/enemies/fish-end.wav",

	GAME.HIGHSCORE: "res://assets/sound/game/highscore.wav",
	GAME.WARN: "res://assets/sound/game/warn.wav",
	GAME.CLICK: "res://assets/sound/game/click.wav"
}

const MUSIC_PATH = "res://assets/sound/game/background.mp3"

var _loaded_sounds = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Initialize Volumes to 50% (User Request)
	_set_bus_volume("Master", 0.5)
	_set_bus_volume("Music", 0.15)
	_set_bus_volume("SFX", 0.5)

	load_sounds()
	_start_background_music()

func _set_bus_volume(bus_name: String, linear_val: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))

func load_sounds() -> void:
	for key in _sound_files:
		var path = _sound_files[key]
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream:
				_loaded_sounds[key] = stream

func play_sound(sound_id: String) -> void:
	if not _loaded_sounds.has(sound_id):
		return

	var stream = _loaded_sounds[sound_id]
	var player = _get_available_sfx_player()
	player.stream = stream
	player.bus = "SFX"

	if sound_id == AudioManager.WOOL.HOOK:
		player.volume_db = linear_to_db(0.15)
	elif sound_id == AudioManager.ENEMIES.FISH_END:
		player.volume_db = linear_to_db(0.5)
	else:
		player.volume_db = 0.0

	if sound_id.begins_with("ui_") or sound_id.begins_with("game_"):
		player.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		player.process_mode = Node.PROCESS_MODE_INHERIT

	player.play()

func get_sound_stream(sound_id: String) -> AudioStream:
	if not _loaded_sounds.has(sound_id):
		return null
	return _loaded_sounds[sound_id]

func _get_available_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p

	var new_player = AudioStreamPlayer.new()
	# Default to INHERIT (pausable)
	add_child(new_player)
	_sfx_pool.append(new_player)
	return new_player

func create_audio_player(sound_id: String, parent: Node) -> AudioStreamPlayer:
	if not _loaded_sounds.has(sound_id):
		return null

	var new_player = AudioStreamPlayer.new()
	# Specific players (like for enemies) should generally pause with the game
	# unless specified otherwise. Default to INHERIT.
	if sound_id.begins_with("ui_") or sound_id.begins_with("game_"):
		new_player.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		new_player.process_mode = Node.PROCESS_MODE_INHERIT

	parent.add_child(new_player)
	new_player.stream = _loaded_sounds[sound_id]
	new_player.bus = "SFX"
	if sound_id == AudioManager.ENEMIES.BIRD:
		new_player.volume_db = linear_to_db(0.15)
	if sound_id == AudioManager.ENEMIES.SPUCKI:
		new_player.volume_db = linear_to_db(0.75)
	if sound_id == AudioManager.ENEMIES.FISH_START:
		new_player.volume_db = linear_to_db(0.75)
	if sound_id == AudioManager.ENEMIES.FISH_END:
		new_player.volume_db = linear_to_db(1.0)
	return new_player

func _start_background_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		return

	var stream = load(MUSIC_PATH)
	if stream is AudioStreamMP3:
		stream.loop = true

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = stream
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	_music_player.play()
