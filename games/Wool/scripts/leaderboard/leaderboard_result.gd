class_name LeaderboardResult
extends RefCounted

## Uniform return value for every LeaderboardBackend call.
##
## Backends never throw and never return null - callers always get a result they
## can branch on, which keeps the window's error state handling simple.

enum Code {
	OK,
	NETWORK,
	AUTH,
	REJECTED,
	NOT_CONFIGURED,
	TIMEOUT,
	UNKNOWN,
}

var ok: bool = false
var code: Code = Code.UNKNOWN
var message: String = ""
var entries: Array[LeaderboardEntry] = []

static func success(p_entries: Array[LeaderboardEntry] = []) -> LeaderboardResult:
	var result: LeaderboardResult = LeaderboardResult.new()
	result.ok = true
	result.code = Code.OK
	result.entries = p_entries
	return result

static func failure(p_code: Code, p_message: String) -> LeaderboardResult:
	var result: LeaderboardResult = LeaderboardResult.new()
	result.ok = false
	result.code = p_code
	result.message = p_message
	return result

## Short, player-facing text. The detailed message goes to the log, not the screen.
func get_display_message() -> String:
	match code:
		Code.OK:
			return ""
		Code.NETWORK:
			return "No connection"
		Code.TIMEOUT:
			return "Connection timed out"
		Code.AUTH:
			return "Could not sign in"
		Code.REJECTED:
			return "Score was rejected"
		Code.NOT_CONFIGURED:
			return "Leaderboard unavailable"
		_:
			return "Something went wrong"
