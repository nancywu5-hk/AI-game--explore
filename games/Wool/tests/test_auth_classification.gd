extends SceneTree

## Headless checks for the two rules that decide whether a leaderboard identity
## is thrown away.
##
##     godot --headless --script tests/test_auth_classification.gd
##
## Both rules are static and side-effect free precisely so they can be exercised
## without a network. Getting either wrong fails silently in production: the
## player keeps playing, and a row stays on the board under their own name that
## nothing they own can delete. That is the bug this file exists to keep buried.

const Backend: GDScript = preload("res://scripts/leaderboard/backends/firebase_leaderboard_backend.gd")
const Result: GDScript = preload("res://scripts/leaderboard/leaderboard_result.gd")

const DAY: int = 24 * 60 * 60
const NOW: int = 1_800_000_000

var _failures: int = 0

func _init() -> void:
	_test_classify_refresh_failure()
	_test_identity_staleness()

	if _failures > 0:
		printerr("auth classification: %d check(s) failed" % _failures)
		quit(1)
		return

	print("auth classification: all checks passed")
	quit(0)

func _test_classify_refresh_failure() -> void:
	# Every way securetoken says "this token is spent".
	_expect_code("400 TOKEN_EXPIRED", 400, "TOKEN_EXPIRED", Result.Code.AUTH)
	_expect_code("400 bare", 400, "", Result.Code.AUTH)
	_expect_code("401", 401, "", Result.Code.AUTH)
	_expect_code("403", 403, "", Result.Code.AUTH)

	# ...and every way it merely says "not right now". These are the ones that
	# used to cost a player their identity, so they carry the weight here.
	_expect_code("429 quota", 429, "RESOURCE_EXHAUSTED", Result.Code.UNKNOWN)
	_expect_code("500", 500, "", Result.Code.UNKNOWN)
	_expect_code("503 outage", 503, "backend unavailable", Result.Code.UNKNOWN)
	_expect_code("no status", 0, "", Result.Code.UNKNOWN)

	# The message is the fallback, for a fatal reason arriving under an
	# unexpected status.
	_expect_code("503 with fatal body", 503, "INVALID_REFRESH_TOKEN", Result.Code.AUTH)

func _test_identity_staleness() -> void:
	var threshold: int = Backend.MAX_REFRESH_FAILURES
	var window: int = Backend.IDENTITY_STALE_SECONDS

	# Failures alone are never enough, however many pile up.
	_expect_stale("no failures", 0, NOW - 30 * DAY, false)
	_expect_stale("below threshold", threshold - 1, NOW - 30 * DAY, false)

	# Neither is age alone.
	_expect_stale("stale but healthy", 0, NOW - 400 * DAY, false)

	# Both together, at the boundary and past it.
	_expect_stale("at threshold and window", threshold, NOW - window, true)
	_expect_stale("well past both", threshold + 20, NOW - 400 * DAY, true)
	_expect_stale("failing but recently fine", threshold, NOW - DAY, false)

	# An upgrade from a build that never recorded a success must not read as an
	# expired identity - that would abandon a working account on first launch.
	_expect_stale("no recorded success", 99, 0, false)

	# A clock that jumped forward and back must not age an identity either.
	_expect_stale("success in the future", threshold, NOW + 5 * DAY, false)

func _expect_code(label: String, http_code: int, message: String, expected: int) -> void:
	_check(label, Backend.classify_refresh_failure(http_code, message), expected)

func _expect_stale(label: String, failures: int, last_success_unix: int, expected: bool) -> void:
	_check(label, Backend.is_identity_stale(failures, last_success_unix, NOW), expected)

func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		return
	_failures += 1
	printerr("FAIL %s: expected %s, got %s" % [label, expected, actual])
