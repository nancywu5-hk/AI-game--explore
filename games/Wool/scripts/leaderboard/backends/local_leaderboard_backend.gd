class_name LocalLeaderboardBackend
extends LeaderboardBackend

## On-device leaderboard stored as JSON.
##
## Used whenever no valid Firebase config is present, which keeps the editor,
## CI and offline players on a working code path instead of a dead UI. Also the
## reference implementation of the interface - it is deliberately small enough
## to read in one sitting.

const SAVE_PATH: String = "user://leaderboard_local.json"
## Ten rows rather than a handful: enough to overflow the leaderboard window on
## every screen size, which is what makes the list actually scroll. Kept in
## descending score order for readability - fetch_top() sorts anyway.
const SEED_NAMES: Array[String] = [
	"Zopfmuster", "Wollknäuel", "Nadelöhr", "Schafkopf", "Bommelbär",
	"Flauschi", "Maschenwerk", "Merino", "Filzhut", "Strickliesl",
]
const SEED_SCORES: Array[int] = [945, 820, 735, 610, 528, 455, 382, 300, 244, 175]
const SEED_TIMES_MS: Array[int] = [
	108300, 96400, 88200, 74100, 66700, 58900, 49500, 41200, 33800, 25600,
]

var _player_id: String = ""
var _entries: Array[LeaderboardEntry] = []

func initialize(_config: LeaderboardConfig) -> LeaderboardResult:
	_load()
	if _player_id.is_empty():
		_player_id = "local-%08X" % (randi() & 0x7FFFFFFF)
	if _entries.is_empty():
		_seed_entries()
	_save()
	return LeaderboardResult.success()

func submit(entry: LeaderboardEntry) -> LeaderboardResult:
	if entry == null:
		return LeaderboardResult.failure(LeaderboardResult.Code.REJECTED, "null entry")

	entry.player_id = _player_id
	var existing: LeaderboardEntry = _find_own_entry()

	if existing == null:
		_entries.append(entry)
	elif entry.is_better_than(existing):
		existing.player_name = entry.player_name
		existing.score = entry.score
		existing.duration_ms = entry.duration_ms
		existing.updated_at_unix = entry.updated_at_unix
	else:
		# Not an improvement - mirrors what the Firestore rules would reject.
		return LeaderboardResult.success()

	_save()
	return LeaderboardResult.success()

func fetch_top(limit: int) -> LeaderboardResult:
	var sorted: Array[LeaderboardEntry] = _entries.duplicate()
	sorted.sort_custom(LeaderboardEntry.sort_desc)

	var result: Array[LeaderboardEntry] = []
	for index in range(min(limit, sorted.size())):
		var entry: LeaderboardEntry = sorted[index]
		entry.rank = index + 1
		result.append(entry)

	return LeaderboardResult.success(result)

func fetch_player() -> LeaderboardResult:
	var own: LeaderboardEntry = _find_own_entry()
	if own == null:
		return LeaderboardResult.success()

	var sorted: Array[LeaderboardEntry] = _entries.duplicate()
	sorted.sort_custom(LeaderboardEntry.sort_desc)
	own.rank = sorted.find(own) + 1

	var result: Array[LeaderboardEntry] = [own]
	return LeaderboardResult.success(result)

func rename(new_name: String) -> LeaderboardResult:
	var own: LeaderboardEntry = _find_own_entry()
	if own == null:
		return LeaderboardResult.success()

	own.player_name = new_name
	own.updated_at_unix = int(Time.get_unix_time_from_system())
	_save()
	return LeaderboardResult.success()

## Drops this player's row and issues a new id, mirroring what the Firebase
## backend does when it deletes the anonymous account: the next run publishes as
## a stranger rather than reoccupying the deleted slot. The seeded rows stay -
## they are scenery, not other people's data.
func delete_entry() -> LeaderboardResult:
	var own: LeaderboardEntry = _find_own_entry()
	if own != null:
		_entries.erase(own)

	_player_id = "local-%08X" % (randi() & 0x7FFFFFFF)
	_save()
	return LeaderboardResult.success()

func get_player_id() -> String:
	return _player_id

func _find_own_entry() -> LeaderboardEntry:
	for entry in _entries:
		if entry.player_id == _player_id:
			return entry
	return null

## Gives a first-run player something to measure themselves against instead of
## an empty list.
func _seed_entries() -> void:
	for index in range(SEED_NAMES.size()):
		_entries.append(LeaderboardEntry.create(
			"seed-%d" % index,
			SEED_NAMES[index],
			SEED_SCORES[index],
			SEED_TIMES_MS[index]
		))

func _load() -> void:
	_entries.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("LocalLeaderboardBackend: cannot read %s" % SAVE_PATH)
		return

	var raw: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_warning("LocalLeaderboardBackend: malformed save, starting fresh")
		return

	var data: Dictionary = parsed
	_player_id = str(data.get("player_id", ""))

	var stored: Variant = data.get("entries", [])
	if not stored is Array:
		return
	for item in stored:
		if item is Dictionary:
			_entries.append(LeaderboardEntry.from_dict(item))

func _save() -> void:
	var serialized: Array[Dictionary] = []
	for entry in _entries:
		serialized.append(entry.to_dict())

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("LocalLeaderboardBackend: cannot write %s" % SAVE_PATH)
		return

	file.store_string(JSON.stringify({
		"player_id": _player_id,
		"entries": serialized,
	}))
	file.close()
