class_name LeaderboardEntry
extends RefCounted

## A single leaderboard row.
##
## Ranking rule lives here and nowhere else: more meters wins, and on a tie the
## shorter run time wins. GameManager, both backends and the UI all defer to
## is_better_than() so the rule can never drift between them.

const MAX_NAME_LENGTH: int = 16

var player_id: String = ""
var player_name: String = ""
var score: int = 0
var duration_ms: int = 0
var updated_at_unix: int = 0
var rank: int = 0

static func create(p_id: String, p_name: String, p_score: int, p_duration_ms: int) -> LeaderboardEntry:
	var entry: LeaderboardEntry = LeaderboardEntry.new()
	entry.player_id = p_id
	entry.player_name = p_name
	entry.score = p_score
	entry.duration_ms = p_duration_ms
	entry.updated_at_unix = int(Time.get_unix_time_from_system())
	return entry

## THE ordering rule. Higher score wins; equal score is broken by faster time.
## A non-positive duration means "unknown" and always loses a tie-break.
static func is_better(a_score: int, a_duration_ms: int, b_score: int, b_duration_ms: int) -> bool:
	if a_score != b_score:
		return a_score > b_score
	if a_duration_ms <= 0:
		return false
	if b_duration_ms <= 0:
		return true
	return a_duration_ms < b_duration_ms

## Comparator for Array.sort_custom() - produces best-first order.
static func sort_desc(a: LeaderboardEntry, b: LeaderboardEntry) -> bool:
	return is_better(a.score, a.duration_ms, b.score, b.duration_ms)

## Strip control characters and clamp length so the value survives the
## Firestore security rules (name must be 1..16 chars).
static func sanitize_name(raw: String) -> String:
	var cleaned: String = ""
	for character in raw:
		if character.unicode_at(0) >= 32:
			cleaned += character
	cleaned = cleaned.strip_edges()
	if cleaned.length() > MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_NAME_LENGTH)
	return cleaned

func is_better_than(other: LeaderboardEntry) -> bool:
	if other == null:
		return true
	return LeaderboardEntry.is_better(score, duration_ms, other.score, other.duration_ms)

## Renders duration as m:ss.mmm (e.g. "1:04.382"), matching the millisecond
## precision the ranking actually uses.
func format_time() -> String:
	if duration_ms <= 0:
		return "-"
	var total_seconds: int = duration_ms / 1000
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var millis: int = duration_ms % 1000
	return "%d:%02d.%03d" % [minutes, seconds, millis]

func format_score() -> String:
	return str(score) + "m"

func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"player_name": player_name,
		"score": score,
		"duration_ms": duration_ms,
		"updated_at_unix": updated_at_unix,
	}

static func from_dict(data: Dictionary) -> LeaderboardEntry:
	var entry: LeaderboardEntry = LeaderboardEntry.new()
	entry.player_id = str(data.get("player_id", ""))
	entry.player_name = str(data.get("player_name", ""))
	entry.score = int(data.get("score", 0))
	entry.duration_ms = int(data.get("duration_ms", 0))
	entry.updated_at_unix = int(data.get("updated_at_unix", 0))
	return entry
