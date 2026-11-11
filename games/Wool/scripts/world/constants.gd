extends BaseConstants

const DEFAULT_GRAVITY: float = 1000.0

func _ready() -> void:
	settings = {
		"Physics": {
			"gravity": { "value": DEFAULT_GRAVITY, "min": 0.0, "max": 2000.0, "step": 10.0 }
		}
	}
