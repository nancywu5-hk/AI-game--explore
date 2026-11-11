extends Node

## LeaderboardManager - Global Leaderboard Access
##
## The only leaderboard surface gameplay code touches. All storage work happens
## behind LeaderboardBackend, so swapping Firebase out means changing
## _create_backend() and nothing else.
##
## Nothing here ever blocks gameplay: submits are fire-and-forget, a failed
## submit is queued for the next launch, and fetches are cached so reopening the
## window does not burn Firestore quota.

# === SIGNALS ===
signal top_updated(entries: Array[LeaderboardEntry])
signal submit_finished(result: LeaderboardResult)
signal player_name_changed(new_name: String)
signal availability_changed(available: bool)
signal player_rank_updated(rank: int)
signal entry_deleted(result: LeaderboardResult)
## Publishing was switched on or off. The settings toggle is the only thing that
## starts this, but it arrives back through the signal rather than being assumed:
## switching off completes asynchronously, once the row is actually gone.
signal publish_consent_changed(consented: bool)

# === CONSTANTS ===
const CONFIG_PATH: String = "res://resources/leaderboard_config.tres"
const PLAYER_PATH: String = "user://player.cfg"
const LOCAL_BACKEND_SCRIPT: GDScript = preload("res://scripts/leaderboard/backends/local_leaderboard_backend.gd")
const FIREBASE_BACKEND_SCRIPT: GDScript = preload("res://scripts/leaderboard/backends/firebase_leaderboard_backend.gd")

## Kept short so "noun + 4 digits" always fits LeaderboardEntry.MAX_NAME_LENGTH.
const NAME_NOUNS: Array[String] = [
	"Schaf", "Knäuel", "Faden", "Masche", "Socke", "Wolke", "Nadel", "Zopf",
	"Flausch", "Pompom", "Filz", "Strick", "Garn", "Troddel", "Bommel", "Docke",
]

## Backoff between reconnect attempts, in seconds; the last value repeats forever.
## Godot exposes no connectivity API, so polling is the only way to notice the
## radio came back - the long tail keeps that from costing battery all session.
const RETRY_DELAYS_SECONDS: Array[int] = [5, 15, 60, 180, 600]

## Floor between manual retries. Dying over and over with no signal should not
## turn into one auth round-trip per death.
const MANUAL_RETRY_COOLDOWN_SECONDS: int = 20

# === PUBLIC VARIABLES ===
var player_name: String = ""
var is_available: bool = false
var is_remote: bool = false

# === PRIVATE VARIABLES ===
var _config: LeaderboardConfig = null
var _backend: LeaderboardBackend = null
var _cached_top: Array[LeaderboardEntry] = []
var _player_entry: LeaderboardEntry = null
var _last_fetch_unix: int = 0
## The "Scores veröffentlichen" switch in the settings. While it is off a run
## never leaves the device; while it is on every run publishes on its own.
var _publish_consented: bool = false
var _pending_score: int = 0
var _pending_time_ms: int = 0
var _fetching: bool = false
var _submitting: bool = false
var _renaming: bool = false
var _deleting: bool = false
var _connecting: bool = false
var _availability_settled: bool = false
var _retry_index: int = 0
var _retry_timer: Timer = null
var _last_attempt_unix: int = 0

# === BUILT-IN METHODS ===
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_player_state()
	_build_retry_timer()
	_initialize.call_deferred()

func _notification(what: int) -> void:
	# Returning from the background is the likeliest moment for connectivity to
	# have changed, and it is the closest thing to a connection event we get.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		retry_now()

# === PUBLIC METHODS ===

func has_player_name() -> bool:
	return not player_name.is_empty()

## True while the settings switch is on, so every run goes to the global board.
func is_publishing() -> bool:
	return _publish_consented

## Storing a name never publishes anything: with the switch off it is a local
## label and nothing more, which is what lets the player rename themselves
## without being put on the board for it.
func set_player_name(new_name: String) -> void:
	var cleaned: String = LeaderboardEntry.sanitize_name(new_name)
	if cleaned.is_empty() or cleaned == player_name:
		return

	player_name = cleaned
	_save_player_state()
	player_name_changed.emit(player_name)

	# Push the new label to the already-published row, otherwise it would keep
	# the old name until the player next beats their own record.
	_push_rename()

## Turn publishing on - the settings switch. The stored best goes up right away,
## so the switch takes effect now rather than at the next death.
##
## The go-ahead is stored on the press rather than on a successful write. It is
## the player's decision, not the network's: switching on with no signal has to
## publish when the connection returns, not silently do nothing.
##
## A zero score is not an error. submit_run() drops it, so a player who switches
## this on before their first run simply appears once they have something to show.
##
## Switching off is delete_entry(), not this - it has to erase a row that is
## already up, which can fail, so the caller needs the result.
func enable_publishing(score: int, duration_ms: int) -> void:
	if _publish_consented:
		return

	# A row cannot exist without a name. The first-launch prompt guarantees one;
	# this is the backstop for a player.cfg that somehow lost it.
	if not has_player_name():
		set_player_name(_random_name())

	_publish_consented = true
	_save_player_state()
	publish_consent_changed.emit(true)

	# Banks the score, then either sends it or arms a retry. Anything already
	# queued from a run played with the switch off goes up with it.
	submit_run(score, duration_ms)

## Queue a run for upload. Safe to call at any time; returns immediately.
##
## Does nothing beyond banking the score locally while the switch is off - the
## banked run then goes up the moment it is switched on.
func submit_run(score: int, duration_ms: int) -> void:
	if score <= 0 or duration_ms <= 0:
		return

	_remember_pending(score, duration_ms)

	# Held on disk, not dropped: if they later opt in, this run goes up with it.
	if not _publish_consented:
		return

	# Without a name there is nothing valid to write - hold it until they pick one.
	if not has_player_name():
		return

	if not is_available:
		# Already banked to disk. A run just ended, so this is a natural moment
		# to check whether the connection came back; the queued score goes up as
		# soon as it does.
		retry_now()
		return

	_submit_pending()

## Drop the backoff and try to reach the backend right now, flushing anything
## queued if it works. Rate-limited by MANUAL_RETRY_COOLDOWN_SECONDS.
func retry_now() -> void:
	if is_available:
		_flush_pending()
		return

	# An attempt is already running and will arm the next backoff itself. Bailing
	# out here matters: the reset below would otherwise cancel a scheduled retry
	# on behalf of an attempt that never starts, killing the loop entirely.
	if _connecting:
		return

	var now: int = int(Time.get_unix_time_from_system())
	if now - _last_attempt_unix < MANUAL_RETRY_COOLDOWN_SECONDS:
		return

	_retry_index = 0
	if _retry_timer:
		_retry_timer.stop()
	_try_connect()

func refresh_top(force: bool = false) -> void:
	if _fetching:
		return
	if not is_available:
		# Opening the window is a deliberate "show me the board" - worth probing
		# the connection. The result arrives via availability_changed.
		retry_now()
		top_updated.emit(_cached_top)
		return

	var now: int = int(Time.get_unix_time_from_system())
	var cache_age: int = now - _last_fetch_unix
	if not force and not _cached_top.is_empty() and cache_age < _config.cache_seconds:
		top_updated.emit(_cached_top)
		return

	_fetch_top_async()

func get_cached_top() -> Array[LeaderboardEntry]:
	return _cached_top

func get_player_entry() -> LeaderboardEntry:
	return _player_entry

func get_player_id() -> String:
	if _backend == null:
		return ""
	return _backend.get_player_id()

## 0 when the player has no ranked entry.
func get_player_rank() -> int:
	if _player_entry == null:
		return 0
	return _player_entry.rank

## Re-reads this player's standing straight from the backend and returns the
## rank (0 when unranked). Waits out an in-flight submit so the rank reflects
## the run that was just sent.
func refresh_player_rank() -> int:
	if not is_available or _backend == null:
		return 0

	while _submitting:
		await get_tree().process_frame

	var result: LeaderboardResult = await _backend.fetch_player()
	if not result.ok or result.entries.is_empty():
		return 0

	_player_entry = result.entries[0]
	player_rank_updated.emit(_player_entry.rank)
	return _player_entry.rank

## True while an erasure is in flight, so the UI can keep the button disabled
## instead of firing a second delete at an identity that is already gone.
func is_deleting() -> bool:
	return _deleting

## Switch publishing off: erase the published row and the anonymous identity
## behind it, and stop anything local from putting it back.
##
## Clearing the queued run matters as much as the delete itself - a pending
## score left in player.cfg would flush straight back onto the board on the next
## connect, and the player would reasonably conclude the deletion did nothing.
##
## Returns the result rather than swallowing it: the settings switch has to stay
## on when this fails, because the row is still up there.
func delete_entry() -> LeaderboardResult:
	if _backend == null:
		return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "no backend")
	if _deleting:
		return LeaderboardResult.failure(LeaderboardResult.Code.UNKNOWN, "delete already running")
	if not is_available:
		# Deleting is not something to queue for later: the player is owed a clear
		# yes or no, not a promise that something happened while they were away.
		retry_now()
		return LeaderboardResult.failure(LeaderboardResult.Code.NETWORK, "offline")

	_deleting = true
	# Let an in-flight write land first - a submit or rename completing after the
	# delete would recreate the row moments after we removed it.
	while _submitting or _renaming:
		await get_tree().process_frame

	var result: LeaderboardResult = await _backend.delete_entry()
	_deleting = false

	if result.ok:
		_forget_published_entry()
	else:
		push_warning("LeaderboardManager: delete failed (%s)" % result.message)
		_handle_connectivity_failure(result)

	entry_deleted.emit(result)
	return result

## Local half of the erasure.
##
## The name deliberately survives: it is no longer the row's, it is the player's
## - asked for once at first launch and owned in the settings from then on.
## Switching publishing back on republishes under it, with no run in between.
func _forget_published_entry() -> void:
	_publish_consented = false
	# A queued run would flush straight back onto the board on the next connect.
	_pending_score = 0
	_pending_time_ms = 0
	_player_entry = null
	_save_player_state()

	# The board no longer contains our row - never serve a cached list that does.
	_cached_top.clear()
	_last_fetch_unix = 0

	# Settles the settings toggle into its off state, now that the row is gone.
	publish_consent_changed.emit(_publish_consented)

func is_using_remote_backend() -> bool:
	return is_remote

## A suggested display name.
##
## Purely local and instant: rows are keyed by document id, so two players
## sharing a name collide on screen at worst, and the leaderboard marks your own
## row with "(You)" to keep that unambiguous.
func generate_name() -> String:
	return _random_name()

func _push_rename() -> void:
	# The switch is off, so there is no row to relabel - and writing one from here
	# would put the player on the board purely for renaming themselves.
	if not _publish_consented:
		return
	if not is_available or _backend == null or _renaming:
		return

	_renaming = true
	var target: String = player_name
	var result: LeaderboardResult = await _backend.rename(target)
	_renaming = false

	if not result.ok:
		push_warning("LeaderboardManager: rename failed (%s)" % result.message)
		return

	# The visible row changed - do not serve a stale cached list.
	_last_fetch_unix = 0
	if _player_entry != null:
		_player_entry.player_name = target

	# The name moved on while we were waiting; run it again.
	if player_name != target:
		_push_rename()

func _random_name() -> String:
	return "%s%04d" % [NAME_NOUNS[randi() % NAME_NOUNS.size()], randi() % 10000]

# === PRIVATE METHODS ===

func _initialize() -> void:
	_config = _load_config()
	_backend = _create_backend()
	add_child(_backend)
	_try_connect()

## Brings the backend online and flushes anything queued. Safe to call
## repeatedly - initialize() is idempotent on every backend, so this doubles as
## the reconnect path.
func _try_connect() -> void:
	if _connecting or is_available or _backend == null:
		return

	_connecting = true
	_last_attempt_unix = int(Time.get_unix_time_from_system())
	var result: LeaderboardResult = await _backend.initialize(_config)
	_connecting = false

	if not result.ok:
		push_warning("LeaderboardManager: backend unavailable (%s)" % result.message)
		_set_available(false)
		# A missing API key is not going to appear by waiting - only retry the
		# failures that a working connection would actually fix.
		if result.code != LeaderboardResult.Code.NOT_CONFIGURED:
			_schedule_retry()
		return

	_retry_index = 0
	# Our standing may have moved while we were offline; do not serve stale data.
	_last_fetch_unix = 0
	_set_available(true)
	_flush_pending()

## Emits availability_changed on every flip, and once when the first connection
## attempt resolves so listeners get an initial value either way.
func _set_available(value: bool) -> void:
	if is_available == value and _availability_settled:
		return
	is_available = value
	_availability_settled = true
	availability_changed.emit(is_available)

func _build_retry_timer() -> void:
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	# Modal windows pause the tree, so a plain Timer would stall while the
	# leaderboard or pause menu is open - exactly when a retry matters most.
	_retry_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_retry_timer.timeout.connect(_try_connect)
	add_child(_retry_timer)

func _schedule_retry() -> void:
	if is_available or _retry_timer == null:
		return

	var index: int = mini(_retry_index, RETRY_DELAYS_SECONDS.size() - 1)
	_retry_index += 1
	_retry_timer.start(float(RETRY_DELAYS_SECONDS[index]))

## Push a queued run, if there is one, it has a name to travel under, and the
## player has agreed to it being up there at all.
func _flush_pending() -> void:
	if _publish_consented and _pending_score > 0 and has_player_name():
		_submit_pending()

## A failed call is the only connectivity signal available. Drop back to offline
## on the codes a returning connection would fix, so the backoff loop takes over
## and the queued run gets retried; a rejected write is not a network problem.
func _handle_connectivity_failure(result: LeaderboardResult) -> void:
	match result.code:
		LeaderboardResult.Code.NETWORK, LeaderboardResult.Code.TIMEOUT, LeaderboardResult.Code.AUTH:
			_set_available(false)
			_schedule_retry()

func _load_config() -> LeaderboardConfig:
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded: Resource = load(CONFIG_PATH)
		if loaded is LeaderboardConfig:
			return loaded
		push_warning("LeaderboardManager: %s is not a LeaderboardConfig" % CONFIG_PATH)
	return LeaderboardConfig.new()

func _create_backend() -> LeaderboardBackend:
	if _config.is_valid():
		is_remote = true
		return FIREBASE_BACKEND_SCRIPT.new()

	is_remote = false
	return LOCAL_BACKEND_SCRIPT.new()

func _fetch_top_async() -> void:
	_fetching = true
	var result: LeaderboardResult = await _backend.fetch_top(_config.top_limit)

	if result.ok:
		_cached_top = result.entries
		_last_fetch_unix = int(Time.get_unix_time_from_system())
		await _refresh_player_entry()
	else:
		push_warning("LeaderboardManager: fetch_top failed (%s)" % result.message)
		_handle_connectivity_failure(result)

	_fetching = false
	top_updated.emit(_cached_top)

func _refresh_player_entry() -> void:
	var own_id: String = get_player_id()
	if own_id.is_empty():
		return

	# If we are already in the fetched page, no extra read is needed.
	for entry in _cached_top:
		if entry.player_id == own_id:
			_player_entry = entry
			return

	var result: LeaderboardResult = await _backend.fetch_player()
	if result.ok and not result.entries.is_empty():
		_player_entry = result.entries[0]

func _submit_pending() -> void:
	if _submitting or not is_available or _pending_score <= 0:
		return

	_submitting = true
	var entry: LeaderboardEntry = LeaderboardEntry.create(
		get_player_id(), player_name, _pending_score, _pending_time_ms
	)
	var result: LeaderboardResult = await _backend.submit(entry)
	_submitting = false

	# REJECTED means the rules refused it - virtually always "not an
	# improvement". Retrying would fail identically, so drop it.
	if result.ok or result.code == LeaderboardResult.Code.REJECTED:
		_clear_pending()
		# Our standing changed; next open should re-read rather than show stale data.
		_last_fetch_unix = 0
	else:
		# Stays queued in player.cfg, so it survives even if the app is killed.
		push_warning("LeaderboardManager: submit deferred (%s)" % result.message)
		_handle_connectivity_failure(result)

	submit_finished.emit(result)

func _remember_pending(score: int, duration_ms: int) -> void:
	# Keep only the best queued run, using the same rule the leaderboard sorts by.
	if not LeaderboardEntry.is_better(score, duration_ms, _pending_score, _pending_time_ms):
		return
	_pending_score = score
	_pending_time_ms = duration_ms
	_save_player_state()

func _clear_pending() -> void:
	_pending_score = 0
	_pending_time_ms = 0
	_save_player_state()

func _load_player_state() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(PLAYER_PATH) != OK:
		return
	player_name = str(config_file.get_value("player", "name", ""))
	# The key predates nothing for players upgrading from a build that published
	# on its own: a stored name is exactly what "already on the board" looked like
	# back then, and defaulting them to off would leave that row behind with no
	# switch pointing at it. Every build since writes the key explicitly.
	_publish_consented = bool(config_file.get_value(
		"player", "published", not player_name.is_empty()
	))
	_pending_score = int(config_file.get_value("player", "pending_score", 0))
	_pending_time_ms = int(config_file.get_value("player", "pending_time_ms", 0))

func _save_player_state() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.set_value("player", "name", player_name)
	config_file.set_value("player", "published", _publish_consented)
	config_file.set_value("player", "pending_score", _pending_score)
	config_file.set_value("player", "pending_time_ms", _pending_time_ms)
	config_file.save(PLAYER_PATH)
