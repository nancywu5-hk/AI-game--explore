extends BaseConstants

const DEFAULT_MOVE_SPEED: float = 550.0
const IDLE_ANIMATION_DELAY: float = 2.0

func _ready() -> void:
	settings = {
		"Player": {
			"move_speed": { "value": DEFAULT_MOVE_SPEED, "min": 50.0, "max": 1000.0, "step": 10.0, "description": "Basis-Laufgeschwindigkeit am Boden" },
			"jump_velocity": { "value": 1000.0, "min": 100.0, "max": 5000.0, "step": 10.0, "description": "Stärke des Sprungs" },
			"fall_gravity_multiplier": { "value": 2.0, "min": 0.3, "max": 5.0, "step": 0.1, "description": "Schwerkraft beim Fallen. Höher = schneller auf Endgeschwindigkeit, also kürzere Kurve und früher gerade" },
			"max_fall_speed": { "value": 900.0, "min": 0.0, "max": 3000.0, "step": 25.0, "description": "Endgeschwindigkeit beim Fallen. Ab hier fällt Wool gleichmäßig, was den Flug gerade statt gebogen aussehen lässt. 0 = kein Limit" },
			"acceleration": { "value": 5000.0, "min": 1000.0, "max": 10000.0, "step": 50.0, "description": "Wie schnell Wool auf Höchstgeschwindigkeit kommt" },
			"friction": { "value": 500.0, "min": 100.0, "max": 5000.0, "step": 50.0, "description": "Bremskraft am Boden" },
			"air_friction": { "value": 100.0, "min": 100.0, "max": 5000.0, "step": 25.0, "description": "Bremskraft in der Luft - klein halten, sonst frisst sie den Schwung aus Sprung und Grapple" },
			"min_move_speed": { "value": 0.0, "min": 0.0, "max": 1000.0, "step": 10.0, "description": "Mindest-Tempo, unter das Reibung nicht bremst, solange Wool vorwärts rollt. 0 = aus" },
			"camera_zoom": { "value": 1.0, "min": 0.1, "max": 10.0, "step": 0.1, "description": "Zoom-Faktor der Kamera (kleiner ist näher)" }
		},
		"Enemy": {
		}
	}
