class_name HttpJsonClient
extends Node

## Thin await-able wrapper around HTTPRequest.
##
## Exists so the Firebase backend reads as a sequence of REST calls instead of
## signal plumbing. Serialises requests through one HTTPRequest node, because a
## single HTTPRequest cannot handle overlapping calls.

const DEFAULT_TIMEOUT: float = 10.0

var _http: HTTPRequest = null
var _busy: bool = false

## Returns { "error": Error, "code": int, "body": Variant }.
## "error" is OK only when the transport succeeded; "code" is the HTTP status.
func request_json(method: HTTPClient.Method, url: String, headers: PackedStringArray, body: Variant = null) -> Dictionary:
	var payload: String = ""
	if body != null:
		payload = JSON.stringify(body)

	var full_headers: PackedStringArray = headers.duplicate()
	full_headers.append("Content-Type: application/json")

	return await request_raw(method, url, full_headers, payload)

func request_raw(method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
	while _busy:
		await get_tree().process_frame

	_busy = true
	var response: Dictionary = await _perform(method, url, headers, body)
	_busy = false
	return response

func _perform(method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	_ensure_http()

	var start_error: Error = _http.request(url, headers, method, body)
	if start_error != OK:
		return {"error": start_error, "code": 0, "body": null, "transport": -1}

	var completed: Array = await _http.request_completed
	var result: int = completed[0]
	var code: int = completed[1]
	var raw: PackedByteArray = completed[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": FAILED, "code": code, "body": null, "transport": result}

	var text: String = raw.get_string_from_utf8()
	var parsed: Variant = null
	if not text.is_empty():
		parsed = JSON.parse_string(text)
		if parsed == null:
			# Non-JSON body (HTML error page, empty 204). Keep the text for logs.
			parsed = text

	return {"error": OK, "code": code, "body": parsed, "transport": result}

func _ensure_http() -> void:
	if _http != null and is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.timeout = DEFAULT_TIMEOUT
	# Godot's web build routes this through fetch(); gzip is handled by the browser.
	_http.accept_gzip = true
	add_child(_http)
