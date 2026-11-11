class_name LeaderboardConfig
extends Resource

## Backend configuration, authored as resources/leaderboard_config.tres.
##
## The Firebase Web API key is a public project identifier, not a credential -
## it ships inside every client binary by design, and all enforcement lives in
## the Firestore security rules. Committing this resource is intended.
##
## Leaving project_id or api_key empty makes LeaderboardManager fall back to the
## local backend, which is how the editor and CI run without credentials.

@export var project_id: String = ""
@export var api_key: String = ""
@export var collection: String = "scores"
@export_range(1, 100) var top_limit: int = 50
@export_range(0, 3600) var cache_seconds: int = 120

func is_valid() -> bool:
	return not project_id.strip_edges().is_empty() and not api_key.strip_edges().is_empty()
