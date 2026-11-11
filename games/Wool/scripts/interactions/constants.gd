extends BaseConstants


const DEFAULT_HIGHLIGHT_COLOR: Color = Color(1.5, 1.5, 1.5, 1.0)
const DEFAULT_NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const DEFAULT_RUSTY_NAIL_COLOR: Color = Color(1.0, 1.0, 0.0, 1.0)

func _ready() -> void:
	settings = {
		"Visuals": {
			"highlight_nail_color": { "value": DEFAULT_HIGHLIGHT_COLOR, "type": "color" },
			"nail_color": { "value": DEFAULT_NORMAL_COLOR, "type": "color" },
			"rusty_nail_color": { "value": DEFAULT_RUSTY_NAIL_COLOR, "type": "color" }
		}
	}
