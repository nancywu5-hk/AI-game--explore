class_name LeaderboardBackend
extends Node

## Abstract leaderboard storage. All game code talks to this, never to a
## concrete implementation - swapping Firebase for anything else means writing
## one new subclass and changing LeaderboardManager._create_backend().
##
## Extends Node rather than RefCounted because implementations need to parent an
## HTTPRequest into the scene tree; LeaderboardManager add_child()s the backend.
##
## Every method is a coroutine and returns a LeaderboardResult - implementations
## must never return null and never leave the caller awaiting forever.

func initialize(_config: LeaderboardConfig) -> LeaderboardResult:
	push_error("LeaderboardBackend.initialize() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## Persist a run. Implementations only keep it if it beats the stored entry
## under LeaderboardEntry.is_better().
func submit(_entry: LeaderboardEntry) -> LeaderboardResult:
	push_error("LeaderboardBackend.submit() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## Best-first entries, already sorted and rank-stamped (rank starts at 1).
func fetch_top(_limit: int) -> LeaderboardResult:
	push_error("LeaderboardBackend.fetch_top() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## This player's own stored entry, or an ok result with empty entries if they
## have never submitted.
func fetch_player() -> LeaderboardResult:
	push_error("LeaderboardBackend.fetch_player() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## Relabel the existing entry without touching the run it recorded. Succeeds
## as a no-op when nothing has been published yet.
func rename(_new_name: String) -> LeaderboardResult:
	push_error("LeaderboardBackend.rename() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## Erase this install's published entry and the identity behind it, so nothing
## on the backend still points at this player. Succeeds as a no-op when nothing
## has been published yet - the caller asked for an end state, not an event.
##
## Implementations must leave the backend usable afterwards: playing again
## creates a fresh identity rather than resurrecting the deleted one.
func delete_entry() -> LeaderboardResult:
	push_error("LeaderboardBackend.delete_entry() is abstract")
	return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "abstract backend")

## Stable identifier for this install. Empty until initialize() succeeds.
func get_player_id() -> String:
	return ""
