class_name FirebaseLeaderboardBackend
extends LeaderboardBackend

## Firestore leaderboard over plain REST - no SDK, no addon.
##
## Identity comes from Firebase Anonymous Auth; the resulting UID is also the
## document id, which is what lets the security rules enforce one row per
## install and monotonically improving scores.
##
## That makes the identity precious. A row can only ever be rewritten or removed
## by the account that published it, so an identity discarded for a transient
## reason strands a row on the board forever - under the player's own name, and
## beyond the reach of their own delete button. Two guards stand against that:
## a failed refresh only counts as "identity lost" when the server says so or
## when the board is demonstrably reachable while our auth alone keeps failing,
## and an identity that is replaced anyway is parked rather than overwritten, so
## a later launch can still delete what it published.
##
## Auth state lives in its own file rather than sharing LeaderboardManager's
## player.cfg: ConfigFile is load-modify-save, and the two writers straddle
## await points, so a shared file could be clobbered.

const AUTH_PATH: String = "user://firebase_auth.cfg"
const SIGNUP_URL: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const REFRESH_URL: String = "https://securetoken.googleapis.com/v1/token?key=%s"
const DELETE_ACCOUNT_URL: String = "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=%s"
const FIRESTORE_BASE: String = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents"

## Refresh a little before the hour is up so a long request cannot straddle expiry.
const TOKEN_SKEW_SECONDS: int = 120

## Refresh failures the server never called fatal, tolerated before the identity
## is even considered lost. Deliberately more than a bad afternoon's worth.
const MAX_REFRESH_FAILURES: int = 5

## ...and how long the last working sign-in has to be behind us on top of that.
## Both have to hold before a reachability probe gets a say.
const IDENTITY_STALE_SECONDS: int = 7 * 24 * 60 * 60

## Firebase rejects a spent refresh token with one of these, whatever status code
## it happens to arrive under. Checked as a fallback to the status code, never
## instead of it - a wording change upstream must not resurrect the old bug.
const FATAL_REFRESH_ERRORS: Array[String] = [
	"TOKEN_EXPIRED", "USER_DISABLED", "USER_NOT_FOUND",
	"INVALID_REFRESH_TOKEN", "MISSING_REFRESH_TOKEN", "INVALID_GRANT_TYPE",
]

## Parked identities kept at once. Three is already generous: each one costs a
## request per launch until it is reaped, and anything older than that is the
## Firestore TTL's problem rather than the client's.
const MAX_ORPHANS: int = 3

## How far ahead each row's expires_at is stamped, for the Firestore TTL policy
## to act on. The safety net under the orphan reaper: it sweeps up rows whose
## owner cannot reach them any more, which after this covers only installs that
## lost user:// outright or never ran a build with the reaper in it.
##
## Long on purpose. A row lapsing is indistinguishable from a deleted one to the
## player who owns it, so the cost of cutting this too fine is the very bug this
## whole file is about.
const ENTRY_TTL_SECONDS: int = 365 * 24 * 60 * 60

var _config: LeaderboardConfig = null
var _client: HttpJsonClient = null
var _uid: String = ""
var _id_token: String = ""
var _refresh_token: String = ""
var _token_expires_unix: int = 0
## Consecutive refresh failures the server did not call fatal.
var _refresh_failures: int = 0
## When this install last held a working token - the clock staleness runs on.
var _last_auth_success_unix: int = 0
## Credentials of identities whose published row still needs removing, as
## dictionaries of "uid" and "refresh_token".
var _orphans: Array = []
## Serialises token acquisition. Two callers racing here would each sign up, and
## the loser's uid would be overwritten - orphaning a row for no reason at all.
var _auth_busy: bool = false
var _reaping: bool = false

func initialize(config: LeaderboardConfig) -> LeaderboardResult:
	_config = config
	if _config == null or not _config.is_valid():
		return LeaderboardResult.failure(LeaderboardResult.Code.NOT_CONFIGURED, "missing project_id/api_key")

	# initialize() doubles as reconnect, so it must be safe to call repeatedly:
	# creating a client per attempt would parent a new HTTPRequest every time.
	if _client == null or not is_instance_valid(_client):
		_client = HttpJsonClient.new()
		add_child(_client)

	_load_auth()

	# Before anything speaks as the current identity, settle the debts of previous
	# ones. Awaited but never consulted: a row we could not clean up is nobody's
	# reason to keep the player off the board.
	await _reap_orphans()

	return await _ensure_token()

func submit(entry: LeaderboardEntry) -> LeaderboardResult:
	if entry == null:
		return LeaderboardResult.failure(LeaderboardResult.Code.REJECTED, "null entry")

	var auth: LeaderboardResult = await _ensure_token()
	if not auth.ok:
		return auth

	entry.player_id = _uid
	var url: String = "%s/%s/%s" % [_documents_url(), _config.collection, _uid]
	var body: Dictionary = {
		"fields": {
			"name": {"stringValue": entry.player_name},
			"score": {"integerValue": str(entry.score)},
			"duration_ms": {"integerValue": str(entry.duration_ms)},
			"updated_at": {"timestampValue": _to_rfc3339(entry.updated_at_unix)},
			"expires_at": {
				"timestampValue": _to_rfc3339(entry.updated_at_unix + ENTRY_TTL_SECONDS)
			},
		}
	}

	# No updateMask: PATCH replaces the whole field set, matching the rules'
	# hasOnly() check.
	var response: Dictionary = await _authed_request(HTTPClient.METHOD_PATCH, url, body)

	if response["error"] != OK:
		return _transport_failure(response)

	var code: int = response["code"]
	if code == 200:
		return LeaderboardResult.success()
	if code == 403 or code == 400:
		# Rules said no - almost always "not an improvement". Not retryable.
		return LeaderboardResult.failure(
			LeaderboardResult.Code.REJECTED, _error_text(response)
		)
	if code == 401:
		return LeaderboardResult.failure(LeaderboardResult.Code.AUTH, _error_text(response))

	return LeaderboardResult.failure(
		LeaderboardResult.Code.UNKNOWN, "submit HTTP %d: %s" % [code, _error_text(response)]
	)

func fetch_top(limit: int) -> LeaderboardResult:
	var url: String = "%s:runQuery" % _documents_url()
	var body: Dictionary = {
		"structuredQuery": {
			"from": [{"collectionId": _config.collection}],
			"orderBy": [
				{"field": {"fieldPath": "score"}, "direction": "DESCENDING"},
				{"field": {"fieldPath": "duration_ms"}, "direction": "ASCENDING"},
			],
			"limit": limit,
		}
	}

	var response: Dictionary = await _authed_request(HTTPClient.METHOD_POST, url, body)

	if response["error"] != OK:
		return _transport_failure(response)

	var code: int = response["code"]
	if code != 200:
		return LeaderboardResult.failure(
			LeaderboardResult.Code.UNKNOWN, "fetch_top HTTP %d: %s" % [code, _error_text(response)]
		)

	var payload: Variant = response["body"]
	if not payload is Array:
		return LeaderboardResult.failure(LeaderboardResult.Code.UNKNOWN, "unexpected runQuery payload")

	var entries: Array[LeaderboardEntry] = []
	for element in payload:
		if not element is Dictionary:
			continue
		# Streaming responses include bare {readTime} elements with no document.
		if not element.has("document"):
			continue
		var entry: LeaderboardEntry = _parse_document(element["document"])
		if entry != null:
			entry.rank = entries.size() + 1
			entries.append(entry)

	return LeaderboardResult.success(entries)

func fetch_player() -> LeaderboardResult:
	if _uid.is_empty():
		var auth: LeaderboardResult = await _ensure_token()
		if not auth.ok:
			return auth

	var url: String = "%s/%s/%s" % [_documents_url(), _config.collection, _uid]
	var response: Dictionary = await _authed_request(HTTPClient.METHOD_GET, url)

	if response["error"] != OK:
		return _transport_failure(response)

	var code: int = response["code"]
	if code == 404:
		# Never submitted - not an error.
		return LeaderboardResult.success()
	if code != 200:
		return LeaderboardResult.failure(
			LeaderboardResult.Code.UNKNOWN, "fetch_player HTTP %d" % code
		)

	var entry: LeaderboardEntry = _parse_document(response["body"])
	if entry == null:
		return LeaderboardResult.success()

	await _renew_expiry_if_due(response["body"], entry)

	entry.rank = await _fetch_rank(entry.score, entry.duration_ms)

	var entries: Array[LeaderboardEntry] = [entry]
	return LeaderboardResult.success(entries)

## Push a row's expiry back once it is over halfway to lapsing.
##
## Without this the TTL would eventually delete rows that are perfectly alive.
## A player only rewrites their document by beating their own record, so someone
## who plays every week but never improves would watch their entry vanish - the
## same disappearance this whole rewrite set out to stop, arriving by a different
## road.
##
## The rewrite carries the same score and duration, so the rules admit it under
## isRename() rather than isImprovement(). A row with no expires_at at all
## predates the field and gets one stamped on here.
func _renew_expiry_if_due(document: Variant, entry: LeaderboardEntry) -> void:
	var expires_unix: int = 0
	if document is Dictionary and (document as Dictionary).has("fields"):
		var fields: Variant = (document as Dictionary)["fields"]
		if fields is Dictionary:
			expires_unix = _timestamp_field(fields, "expires_at")

	var now: int = int(Time.get_unix_time_from_system())
	if expires_unix > now + ENTRY_TTL_SECONDS / 2:
		return

	entry.updated_at_unix = now
	var result: LeaderboardResult = await submit(entry)
	if not result.ok:
		# Nothing to escalate: the row keeps the expiry it already had, and the
		# next time the player opens the board this runs again.
		push_warning("FirebaseLeaderboardBackend: expiry renewal failed (%s)" % result.message)

## Rank without downloading the whole collection: count everyone strictly
## better under the ranking rule, then add one.
##
## Two COUNT aggregations rather than one, because "score > mine OR (score ==
## mine AND time < mine)" spans two fields and cannot be expressed as a single
## Firestore filter. Neither count includes the player's own document.
func _fetch_rank(score: int, duration_ms: int) -> int:
	var higher_score: int = await _count_where({
		"fieldFilter": {
			"field": {"fieldPath": "score"},
			"op": "GREATER_THAN",
			"value": {"integerValue": str(score)},
		}
	})
	if higher_score < 0:
		return 0

	var same_but_faster: int = await _count_where({
		"compositeFilter": {
			"op": "AND",
			"filters": [
				{"fieldFilter": {
					"field": {"fieldPath": "score"},
					"op": "EQUAL",
					"value": {"integerValue": str(score)},
				}},
				{"fieldFilter": {
					"field": {"fieldPath": "duration_ms"},
					"op": "LESS_THAN",
					"value": {"integerValue": str(duration_ms)},
				}},
			],
		}
	})
	if same_but_faster < 0:
		return 0

	return higher_score + same_but_faster + 1

## Returns -1 on failure so callers can tell "no rank" from "rank 0".
func _count_where(filter: Dictionary) -> int:
	var url: String = "%s:runAggregationQuery" % _documents_url()
	var body: Dictionary = {
		"structuredAggregationQuery": {
			"structuredQuery": {
				"from": [{"collectionId": _config.collection}],
				"where": filter,
			},
			"aggregations": [{"count": {}, "alias": "n"}],
		}
	}

	var response: Dictionary = await _authed_request(HTTPClient.METHOD_POST, url, body)

	if response["error"] != OK or response["code"] != 200:
		return -1

	var payload: Variant = response["body"]
	if not payload is Array:
		return -1

	for element in payload:
		if not element is Dictionary or not element.has("result"):
			continue
		var result_block: Variant = (element as Dictionary)["result"]
		if not result_block is Dictionary:
			continue
		var fields: Variant = (result_block as Dictionary).get("aggregateFields", {})
		if fields is Dictionary and (fields as Dictionary).has("n"):
			return _int_field(fields, "n")

	return -1

## Re-PATCHes the stored row with the same score and duration but a new name.
## Depends on the isRename() clause in the security rules - without it the write
## is rejected, because isImprovement() alone never permits an equal score.
func rename(new_name: String) -> LeaderboardResult:
	var existing: LeaderboardResult = await fetch_player()
	if not existing.ok:
		return existing

	# Nothing published yet - the new name applies on the first submit anyway.
	if existing.entries.is_empty():
		return LeaderboardResult.success()

	var entry: LeaderboardEntry = existing.entries[0]
	entry.player_name = new_name
	entry.updated_at_unix = int(Time.get_unix_time_from_system())
	return await submit(entry)

## Erases the published row and then the anonymous account that owns it.
##
## Order is not interchangeable: deleting the document needs a valid id token,
## and deleting the account invalidates it. Doing it the other way round would
## strand a row nobody can ever remove, because the rules only accept writes
## from the uid in the document path.
##
## Requires `allow delete: if request.auth.uid == uid;` in the Firestore rules -
## without it every attempt comes back 403 and the player is told it failed.
func delete_entry() -> LeaderboardResult:
	var auth: LeaderboardResult = await _ensure_token()
	if not auth.ok:
		return auth

	# currentDocument.exists=true turns an unconditional delete into a question
	# worth asking. Without it Firestore answers 200 whether or not anything was
	# there, so a delete aimed at an identity we had silently lost reported
	# success while the player's actual row stayed on the board.
	var url: String = "%s/%s/%s?currentDocument.exists=true" % [
		_documents_url(), _config.collection, _uid
	]
	var response: Dictionary = await _authed_request(HTTPClient.METHOD_DELETE, url)

	if response["error"] != OK:
		return _transport_failure(response)

	var code: int = response["code"]
	if code == 200:
		# The row is gone, so the account that owned it has no further purpose.
		await _delete_account()
		return LeaderboardResult.success()

	if code == 404:
		# The precondition failed: this identity has nothing on the board. That is
		# the end state the caller wanted, so it counts as success - but the
		# account has to survive it. Retiring an account that just told us it owns
		# nothing is precisely how a row published by an earlier identity used to
		# become unreachable forever.
		return LeaderboardResult.success()

	if code == 401:
		return LeaderboardResult.failure(LeaderboardResult.Code.AUTH, _error_text(response))
	if code == 403:
		return LeaderboardResult.failure(LeaderboardResult.Code.REJECTED, _error_text(response))
	return LeaderboardResult.failure(
		LeaderboardResult.Code.UNKNOWN, "delete HTTP %d: %s" % [code, _error_text(response)]
	)

func _delete_account() -> void:
	await _retire_account(_id_token)
	_forget_auth()

## Best effort by design: the row is already gone, which is what the player
## asked for. A surviving empty anonymous account is worth a log line, not an
## error that makes them think their score is still on the board.
func _retire_account(id_token: String) -> void:
	if id_token.is_empty():
		return

	var response: Dictionary = await _client.request_json(
		HTTPClient.METHOD_POST,
		DELETE_ACCOUNT_URL % _config.api_key,
		PackedStringArray(),
		{"idToken": id_token}
	)
	if response["error"] != OK or response["code"] != 200:
		push_warning("FirebaseLeaderboardBackend: account delete failed, row already removed")

## Drops the local identity so the next play signs up fresh instead of trying to
## reuse a uid the server no longer knows.
func _forget_auth() -> void:
	_uid = ""
	_id_token = ""
	_refresh_token = ""
	_token_expires_unix = 0
	_refresh_failures = 0
	_last_auth_success_unix = 0

	# Parked identities outlive the one being dropped. They answer for rows this
	# account never owned, and discarding them here would strand those rows.
	if not _orphans.is_empty():
		_save_auth()
		return

	# Passing the user:// path straight through: globalize_path() has nothing
	# meaningful to return on web, where user:// lives in IndexedDB.
	DirAccess.remove_absolute(AUTH_PATH)

func get_player_id() -> String:
	return _uid

# === AUTH ===

## Guarantees a usable id token, minting a new identity only when the current one
## is provably beyond saving.
func _ensure_token() -> LeaderboardResult:
	while _auth_busy:
		await get_tree().process_frame

	# Re-checked after the wait: whoever we queued behind has very likely just
	# fetched the token we were about to go and fetch ourselves.
	if _has_valid_token():
		return LeaderboardResult.success()

	_auth_busy = true
	var result: LeaderboardResult = await _acquire_token()
	_auth_busy = false
	return result

func _has_valid_token() -> bool:
	var now: int = int(Time.get_unix_time_from_system())
	return not _id_token.is_empty() and now < _token_expires_unix - TOKEN_SKEW_SECONDS

## Discards the id token without touching the identity behind it. The refresh
## token is what proves who we are; the id token is a disposable hour-long copy,
## and a server rejecting one is no evidence about the other.
func _invalidate_token() -> void:
	_id_token = ""
	_token_expires_unix = 0

func _acquire_token() -> LeaderboardResult:
	if _refresh_token.is_empty():
		return await _sign_up_anonymously()

	var refreshed: LeaderboardResult = await _refresh_id_token()
	if refreshed.ok:
		return refreshed

	if not await _is_identity_lost(refreshed):
		# Handed back so LeaderboardManager's backoff owns the retry. Signing up
		# here instead is what used to orphan a row over a passing 503.
		return refreshed

	_park_orphan()
	return await _sign_up_anonymously()

## Whether a failed refresh means this identity is gone rather than unlucky.
##
## The server saying so is conclusive. Anything else has to clear a far higher
## bar, because the cost of being wrong is lopsided: waiting costs a player some
## time off the board, while a wrong sign-up permanently strands a row under
## their own name that they can no longer delete.
func _is_identity_lost(failure: LeaderboardResult) -> bool:
	if failure.code == LeaderboardResult.Code.AUTH:
		return true

	_refresh_failures += 1
	_save_auth()

	var now: int = int(Time.get_unix_time_from_system())
	if not is_identity_stale(_refresh_failures, _last_auth_success_unix, now):
		return false

	# Long odds by now: our auth has failed repeatedly across days without the
	# server ever calling the token dead. A read that carries no credentials
	# separates the two remaining explanations - if the board answers, the
	# connection is fine and the fault is ours to give up on.
	return await _can_reach_backend()

## Pure half of the decision above, static and side-effect free so the rule that
## used to orphan rows can be exercised without a network - see
## tests/test_auth_classification.gd.
static func is_identity_stale(failures: int, last_success_unix: int, now_unix: int) -> bool:
	if failures < MAX_REFRESH_FAILURES:
		return false

	# Never recorded a working sign-in. Treated as fresh rather than stale, so an
	# upgrade from a build without the key cannot look like an expired identity.
	if last_success_unix <= 0:
		return false

	return now_unix - last_success_unix >= IDENTITY_STALE_SECONDS

## Sorts a refresh failure into "this token is spent" and "try again later".
##
## The status code leads: securetoken answers 400 for every dead token, and
## 401/403 mean the same thing. Quotas and outages arrive as 429 or 5xx and must
## never cost a player their identity. The message list only catches a fatal
## reason smuggled in under an unexpected status.
static func classify_refresh_failure(http_code: int, message: String) -> LeaderboardResult.Code:
	if http_code == 400 or http_code == 401 or http_code == 403:
		return LeaderboardResult.Code.AUTH

	for fatal in FATAL_REFRESH_ERRORS:
		if message.contains(fatal):
			return LeaderboardResult.Code.AUTH

	return LeaderboardResult.Code.UNKNOWN

## True when the collection answers a read that carries no credentials.
##
## The rules let anyone read the board, which makes this a control group for our
## own auth: it tells a connection problem apart from an identity the server no
## longer honours.
func _can_reach_backend() -> bool:
	var url: String = "%s:runQuery?key=%s" % [_documents_url(), _config.api_key]
	var body: Dictionary = {
		"structuredQuery": {
			"from": [{"collectionId": _config.collection}],
			"limit": 1,
		}
	}

	var response: Dictionary = await _client.request_json(
		HTTPClient.METHOD_POST, url, PackedStringArray(), body
	)
	return response["error"] == OK and int(response["code"]) == 200

## Set the current credentials aside before something replaces them.
##
## The parked refresh token is the only key that will ever open the row this
## identity published - overwriting it, as this code used to, is what made a
## duplicate permanent. _reap_orphans() spends it on a later launch.
func _park_orphan() -> void:
	if _uid.is_empty() or _refresh_token.is_empty():
		return

	_orphans.append({"uid": _uid, "refresh_token": _refresh_token})
	while _orphans.size() > MAX_ORPHANS:
		_orphans.pop_front()

	# Handed over rather than copied. Leaving these current as well would let the
	# reaper delete the row of an identity still in use, in the case where the
	# sign-up meant to replace it never lands - the credentials would then be both
	# parked for deletion and live at the same time.
	_uid = ""
	_id_token = ""
	_refresh_token = ""
	_token_expires_unix = 0
	_refresh_failures = 0
	_last_auth_success_unix = 0
	_save_auth()

## Delete the rows left behind by identities this install has since replaced.
##
## Each is spent under its own credentials, because the rules only accept a
## delete from the uid in the document path. Failure is not fatal: a block stays
## parked until either the row is gone or the account is, so a launch spent
## offline simply tries again next time.
func _reap_orphans() -> void:
	if _orphans.is_empty() or _reaping:
		return

	_reaping = true
	var survivors: Array = []
	for orphan in _orphans:
		if not await _reap_orphan(orphan):
			survivors.append(orphan)
	_orphans = survivors
	_reaping = false
	_save_auth()

## True when this block is settled and can be dropped - either the row is gone,
## or the account that owned it is, which puts the row beyond any reach we have.
func _reap_orphan(orphan: Dictionary) -> bool:
	var uid: String = str(orphan.get("uid", ""))
	var refresh_token: String = str(orphan.get("refresh_token", ""))
	if uid.is_empty() or refresh_token.is_empty():
		return true

	var exchanged: Dictionary = await _exchange_refresh_token(refresh_token)
	if not exchanged["ok"]:
		# Only the server calling the token dead ends the attempt; a network
		# failure leaves the block parked for a luckier launch.
		return exchanged["code"] == LeaderboardResult.Code.AUTH

	var id_token: String = str(exchanged["id_token"])
	var url: String = "%s/%s/%s" % [_documents_url(), _config.collection, uid]
	var headers: PackedStringArray = PackedStringArray(["Authorization: Bearer %s" % id_token])
	var response: Dictionary = await _client.request_json(HTTPClient.METHOD_DELETE, url, headers)

	if response["error"] != OK:
		return false

	var code: int = int(response["code"])
	# No precondition here, unlike delete_entry(): 200 and 404 both mean no row is
	# left behind, which is the whole point of the exercise.
	if code != 200 and code != 404:
		push_warning("FirebaseLeaderboardBackend: orphan cleanup HTTP %d" % code)
		return false

	await _retire_account(id_token)
	return true

## Resets the evidence the staleness check runs on.
func _note_auth_success() -> void:
	_refresh_failures = 0
	_last_auth_success_unix = int(Time.get_unix_time_from_system())

func _sign_up_anonymously() -> LeaderboardResult:
	var url: String = SIGNUP_URL % _config.api_key
	var response: Dictionary = await _client.request_json(
		HTTPClient.METHOD_POST, url, PackedStringArray(), {"returnSecureToken": true}
	)

	if response["error"] != OK:
		return _transport_failure(response)

	if response["code"] != 200:
		return LeaderboardResult.failure(
			LeaderboardResult.Code.AUTH, "signUp HTTP %d: %s" % [response["code"], _error_text(response)]
		)

	var data: Variant = response["body"]
	if not data is Dictionary:
		return LeaderboardResult.failure(LeaderboardResult.Code.AUTH, "signUp returned no JSON")

	_uid = str(data.get("localId", ""))
	_id_token = str(data.get("idToken", ""))
	_refresh_token = str(data.get("refreshToken", ""))
	_token_expires_unix = int(Time.get_unix_time_from_system()) + int(str(data.get("expiresIn", "3600")))

	if _uid.is_empty() or _id_token.is_empty():
		return LeaderboardResult.failure(LeaderboardResult.Code.AUTH, "signUp response missing fields")

	_note_auth_success()
	_save_auth()
	return LeaderboardResult.success()

func _refresh_id_token() -> LeaderboardResult:
	var exchanged: Dictionary = await _exchange_refresh_token(_refresh_token)
	if not exchanged["ok"]:
		return LeaderboardResult.failure(exchanged["code"], str(exchanged["message"]))

	_id_token = str(exchanged["id_token"])
	_token_expires_unix = int(Time.get_unix_time_from_system()) + int(exchanged["expires_in"])

	# Both are echoed back on every refresh, but only overwritten when actually
	# present - a thinned-out response must not blank the identity.
	var rotated: String = str(exchanged["refresh_token"])
	if not rotated.is_empty():
		_refresh_token = rotated
	var user_id: String = str(exchanged["user_id"])
	if not user_id.is_empty():
		_uid = user_id

	_note_auth_success()
	_save_auth()
	return LeaderboardResult.success()

## Trades a refresh token for an id token without touching any state, which is
## what lets the orphan reaper authenticate as an identity this install has
## already replaced.
##
## Returns { "ok": bool, "code": LeaderboardResult.Code, "message": String } and,
## when ok, "id_token", "refresh_token", "user_id" and "expires_in".
func _exchange_refresh_token(refresh_token: String) -> Dictionary:
	if refresh_token.is_empty():
		return {"ok": false, "code": LeaderboardResult.Code.AUTH, "message": "no refresh token"}

	var url: String = REFRESH_URL % _config.api_key
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var body: String = "grant_type=refresh_token&refresh_token=%s" % refresh_token.uri_encode()

	var response: Dictionary = await _client.request_raw(HTTPClient.METHOD_POST, url, headers, body)

	if response["error"] != OK:
		var transport: LeaderboardResult = _transport_failure(response)
		return {"ok": false, "code": transport.code, "message": transport.message}

	var code: int = int(response["code"])
	if code != 200:
		var message: String = _error_text(response)
		return {
			"ok": false,
			"code": classify_refresh_failure(code, message),
			"message": "token refresh HTTP %d: %s" % [code, message],
		}

	var data: Variant = response["body"]
	if not data is Dictionary:
		return {
			"ok": false,
			"code": LeaderboardResult.Code.UNKNOWN,
			"message": "refresh returned no JSON",
		}

	var fields: Dictionary = data
	var id_token: String = str(fields.get("id_token", ""))
	if id_token.is_empty():
		return {
			"ok": false,
			"code": LeaderboardResult.Code.UNKNOWN,
			"message": "refresh response missing id_token",
		}

	return {
		"ok": true,
		"code": LeaderboardResult.Code.OK,
		"message": "",
		"id_token": id_token,
		"refresh_token": str(fields.get("refresh_token", "")),
		"user_id": str(fields.get("user_id", "")),
		"expires_in": int(str(fields.get("expires_in", "3600"))),
	}

func _load_auth() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(AUTH_PATH) != OK:
		return
	_uid = str(config_file.get_value("auth", "uid", ""))
	_refresh_token = str(config_file.get_value("auth", "refresh_token", ""))
	_refresh_failures = int(config_file.get_value("auth", "refresh_failures", 0))
	_last_auth_success_unix = int(config_file.get_value("auth", "last_success_unix", 0))
	_orphans = _sanitize_orphans(config_file.get_value("auth", "orphans", []))

	# Files written before this key existed still carry a token that worked when
	# they were saved. Dating it from now starts the staleness clock at the
	# upgrade, instead of letting a healthy identity look years overdue.
	if _last_auth_success_unix <= 0 and not _refresh_token.is_empty():
		_last_auth_success_unix = int(Time.get_unix_time_from_system())

func _save_auth() -> void:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.set_value("auth", "uid", _uid)
	config_file.set_value("auth", "refresh_token", _refresh_token)
	config_file.set_value("auth", "refresh_failures", _refresh_failures)
	config_file.set_value("auth", "last_success_unix", _last_auth_success_unix)
	config_file.set_value("auth", "orphans", _orphans)
	config_file.save(AUTH_PATH)

## Drops anything that is not a usable credential pair, so a truncated or
## hand-edited file cannot make the reaper loop over junk on every launch.
func _sanitize_orphans(stored: Variant) -> Array:
	var cleaned: Array = []
	if not stored is Array:
		return cleaned

	for element in stored as Array:
		if not element is Dictionary:
			continue
		var entry: Dictionary = element
		var uid: String = str(entry.get("uid", ""))
		var refresh_token: String = str(entry.get("refresh_token", ""))
		if uid.is_empty() or refresh_token.is_empty():
			continue
		cleaned.append({"uid": uid, "refresh_token": refresh_token})

	return cleaned

# === HELPERS ===

func _documents_url() -> String:
	return FIRESTORE_BASE % _config.project_id

func _auth_headers() -> PackedStringArray:
	if _id_token.is_empty():
		return PackedStringArray()
	return PackedStringArray(["Authorization: Bearer %s" % _id_token])

## Performs an authenticated call, renewing the token once if it comes back
## refused.
##
## A 401 says the id token is no good; it says nothing about the identity, which
## lives in the refresh token. Retrying exactly once stops a stale copy from
## turning into a dead session - without it, a rejected token could survive in
## the file across restarts and answer every request with 401 forever - while a
## genuinely rejected identity still fails on the second try rather than looping.
func _authed_request(method: HTTPClient.Method, url: String, body: Variant = null) -> Dictionary:
	var identity: String = _uid
	var response: Dictionary = await _client.request_json(method, url, _auth_headers(), body)
	if response["error"] != OK or int(response["code"]) != 401:
		return response

	_invalidate_token()
	var auth: LeaderboardResult = await _ensure_token()
	if not auth.ok:
		return response

	# Renewing the token turned into a new identity. The caller's url still points
	# at the old uid's document, which this identity has no business writing to,
	# so the original refusal goes back instead of a retry aimed at the wrong row.
	if _uid != identity:
		return response

	return await _client.request_json(method, url, _auth_headers(), body)

func _to_rfc3339(unix_seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_seconds) + "Z"

## Firestore returns integerValue as a JSON *string*, so every numeric field has
## to go through int() rather than being read directly.
func _parse_document(document: Variant) -> LeaderboardEntry:
	if not document is Dictionary:
		return null
	var doc: Dictionary = document
	if not doc.has("fields"):
		return null

	var fields: Variant = doc["fields"]
	if not fields is Dictionary:
		return null

	var entry: LeaderboardEntry = LeaderboardEntry.new()
	entry.player_id = _uid_from_path(str(doc.get("name", "")))
	entry.player_name = _string_field(fields, "name")
	entry.score = _int_field(fields, "score")
	entry.duration_ms = _int_field(fields, "duration_ms")
	entry.updated_at_unix = _timestamp_field(fields, "updated_at")
	return entry

func _uid_from_path(resource_path: String) -> String:
	var segments: PackedStringArray = resource_path.split("/")
	if segments.is_empty():
		return ""
	return segments[segments.size() - 1]

func _string_field(fields: Dictionary, key: String) -> String:
	if not fields.has(key) or not fields[key] is Dictionary:
		return ""
	return str((fields[key] as Dictionary).get("stringValue", ""))

func _int_field(fields: Dictionary, key: String) -> int:
	if not fields.has(key) or not fields[key] is Dictionary:
		return 0
	return int(str((fields[key] as Dictionary).get("integerValue", "0")))

func _timestamp_field(fields: Dictionary, key: String) -> int:
	if not fields.has(key) or not fields[key] is Dictionary:
		return 0
	var raw: String = str((fields[key] as Dictionary).get("timestampValue", ""))
	if raw.is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(raw))

func _transport_failure(response: Dictionary) -> LeaderboardResult:
	var transport: int = int(response.get("transport", -1))
	if transport == HTTPRequest.RESULT_TIMEOUT:
		return LeaderboardResult.failure(LeaderboardResult.Code.TIMEOUT, "request timed out")
	return LeaderboardResult.failure(
		LeaderboardResult.Code.NETWORK, "transport error %d" % transport
	)

func _error_text(response: Dictionary) -> String:
	var body: Variant = response.get("body")
	if body is Dictionary and (body as Dictionary).has("error"):
		var error_object: Variant = (body as Dictionary)["error"]
		if error_object is Dictionary:
			return str((error_object as Dictionary).get("message", "unknown"))
	return "unknown"
